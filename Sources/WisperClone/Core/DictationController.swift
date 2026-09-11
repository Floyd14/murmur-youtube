import WisperDictionary
import WisperFormatting
import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class DictationController {
    enum State: Equatable {
        case idle, starting, listening, finishing
        case error(String)
        var isActive: Bool {
            switch self {
            case .starting, .listening, .finishing: true
            case .idle, .error: false
            }
        }
        var showsHUD: Bool { self != .idle }
    }

    private final class Session {
        let id = UUID()
        let insert: @MainActor (String) async -> TextInjector.Outcome
        var startupTask: Task<Void, Never>?
        var engine: (any TranscriptionEngine)?
        var consumeTask: Task<Void, Never>?
        var feedTask: Task<Void, Never>?
        var finishTask: Task<Void, Never>?
        var recordingWatchdog: Task<Void, Never>?
        var startupWatchdog: Task<Void, Never>?
        var finishingWatchdog: Task<Void, Never>?
        var ingress: AudioIngress?
        var released = false
        init(insert: @escaping @MainActor (String) async -> TextInjector.Outcome) { self.insert = insert }
    }

    private(set) var state: State = .idle
    private(set) var transcript = ""
    private(set) var recoverableTranscript = ""
    private(set) var level: Float = 0
    private let hotkey = HotkeyMonitor()
    private let capture: any AudioCapturing
    private let makeEngine: @MainActor () -> any TranscriptionEngine
    private let requestMicrophone: @MainActor () async -> Bool
    private let insertion: (@MainActor (String) async -> TextInjector.Outcome)?
    private let formatter: (any TextFormatter)?
    private let correct: @MainActor (String) -> String
    private let playSound: @MainActor (String) -> Void
    private let audioCapacity: Int
    private let finishingTimeout: Duration
    private var currentSession: Session?
    private var recoveryExpiry: Task<Void, Never>?

    init(formatter: (any TextFormatter)? = nil,
         makeEngine: @escaping @MainActor () -> any TranscriptionEngine = {
             AppleSpeechEngine(locale: Settings.shared.recognitionLanguage.locale)
         },
         capture: any AudioCapturing = AudioCapture(),
         requestMicrophone: @escaping @MainActor () async -> Bool = { await Permissions.requestMicrophone() },
         insertion: (@MainActor (String) async -> TextInjector.Outcome)? = nil,
         correct: @escaping @MainActor (String) -> String = { DictionaryStore.shared.corrector.apply(to: $0).text },
         playSound: @escaping @MainActor (String) -> Void = { if Settings.shared.soundEnabled { NSSound(named: $0)?.play() } },
         audioCapacity: Int = 512,
         finishingTimeout: Duration = .seconds(15)) {
        self.formatter = formatter
        self.makeEngine = makeEngine
        self.capture = capture
        self.requestMicrophone = requestMicrophone
        self.insertion = insertion
        self.correct = correct
        self.playSound = playSound
        self.audioCapacity = audioCapacity
        self.finishingTimeout = finishingTimeout
    }

    @discardableResult
    func activate() -> Bool {
        hotkey.key = Settings.shared.pushToTalkKey
        hotkey.onPress = { [weak self] in self?.beginDictation() }
        hotkey.onRelease = { [weak self] in self?.endDictation() }
        return hotkey.start()
    }

    func deactivate() {
        hotkey.stop()
        cancelDictation()
        discardRecoveredTranscript()
    }

    @discardableResult
    func reloadHotkey() -> Bool {
        cancelDictation()
        hotkey.stop()
        return activate()
    }

    func startButtonRecording() { beginDictation() }
    func stopButtonRecording() { endDictation() }

    func copyRecoveredTranscript() {
        guard !recoverableTranscript.isEmpty else { return }
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(recoverableTranscript, forType: .string) {
            discardRecoveredTranscript()
            if !state.isActive { state = .idle }
        }
    }

    func discardRecoveredTranscript() {
        recoveryExpiry?.cancel()
        recoveryExpiry = nil
        recoverableTranscript = ""
    }

    private func retainForRecovery(_ text: String) {
        discardRecoveredTranscript()
        recoverableTranscript = text
        recoveryExpiry = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(300)) } catch { return }
            self?.recoverableTranscript = ""
        }
    }

    private func beginDictation() {
        guard !state.isActive else { return }
        let target = TextInjector.captureTarget()
        let session = Session(insert: insertion ?? { await TextInjector.insert($0, into: target) })
        let id = session.id
        currentSession = session
        state = .starting
        transcript = ""
        let pressedAt = ContinuousClock.now
        let ingress = AudioIngress(capacity: audioCapacity) { [weak self] in
            Task { @MainActor in self?.failIfCurrent(id, error: TranscriptionError.audioBufferOverflow) }
        }
        session.ingress = ingress
        // The event-tap callback returns before starting AVAudioEngine.
        session.startupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { session.startupWatchdog?.cancel(); session.startupWatchdog = nil }
            do {
                guard await self.requestMicrophone() else {
                    self.fail("Accesso al microfono disattivato. Abilitalo nelle Impostazioni di Sistema.", session: session)
                    return
                }
                guard self.currentSession === session, !session.released else { return }
                try self.capture.start(
                    onBuffer: { ingress.yield($0) },
                    onLevel: { [weak self] value in
                        Task { @MainActor in
                            guard let self, self.currentSession?.id == id, self.state == .listening else { return }
                            self.level += (value - self.level) * 0.35
                        }
                    },
                    onFailure: { [weak self] in
                        Task { @MainActor in self?.failIfCurrent(id, error: TranscriptionError.captureFailed) }
                    }
                )
                self.state = .listening
                let elapsed = pressedAt.duration(to: .now)
                Log.audio.info("press to capture start: \(String(describing: elapsed), privacy: .public)")
                self.playSound("Tink")
                session.recordingWatchdog = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(300)) } catch { return }
                    guard let self, self.currentSession === session, !session.released else { return }
                    self.endDictation()
                }
                session.startupWatchdog = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    self?.failIfCurrent(id, error: TranscriptionError.timedOut)
                }
                let engine = self.makeEngine()
                session.engine = engine
                let chunks = try await engine.start()
                guard self.currentSession === session else { await engine.cancel(); return }
                session.consumeTask = Task { @MainActor [weak self] in
                    do {
                        for try await chunk in chunks {
                            guard let self, self.currentSession === session else { return }
                            self.transcript = chunk.text
                        }
                    } catch { self?.failIfCurrent(id, error: error) }
                }
                guard let format = await engine.preferredInputFormat() else { throw TranscriptionError.noAudioFormat }
                guard self.currentSession === session else { return }
                session.feedTask = Task.detached(priority: .userInitiated) { [weak self] in
                    let converter = OrderedAudioConverter(outputFormat: format)
                    do {
                        for try await chunk in ingress.stream {
                            try Task.checkCancellation()
                            for converted in try converter.convert(chunk) { try await engine.feed(converted) }
                        }
                        try Task.checkCancellation()
                        for tail in try converter.finish() { try await engine.feed(tail) }
                    } catch { await self?.failIfCurrent(id, error: error) }
                }
            } catch { self.failIfCurrent(id, error: error) }
        }
    }

    private func endDictation() {
        guard state.isActive, let session = currentSession, !session.released else { return }
        session.released = true
        state = .finishing
        session.recordingWatchdog?.cancel()
        capture.stop()
        session.ingress?.finish()
        level = 0
        session.finishingWatchdog = Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await Task.sleep(for: self.finishingTimeout) } catch { return }
            self.failIfCurrent(session.id, error: TranscriptionError.timedOut)
        }
        session.finishTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Releasing while the model starts must not discard already captured audio.
            await session.startupTask?.value
            guard self.currentSession === session else { return }
            await session.feedTask?.value
            guard self.currentSession === session else { return }
            guard session.ingress?.hasCapturedAudio == true, let engine = session.engine else {
                self.resetToIdle(session: session)
                return
            }
            do { try await engine.finish() }
            catch { self.failIfCurrent(session.id, error: error); return }
            await session.consumeTask?.value
            guard self.currentSession === session else { return }
            session.engine = nil
            let raw = self.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { self.resetToIdle(session: session); return }
            let selectedFormatter: any TextFormatter = self.formatter ?? (Settings.shared.smartCleanup
                ? FoundationModelFormatter() as any TextFormatter : RuleBasedFormatter())
            let cleaned = Settings.shared.cleanupEnabled ? await selectedFormatter.format(raw) : raw
            guard self.currentSession === session else { return }
            let output = self.correct(cleaned)
            // Keep the produced text before attempting a cross-process write.
            self.retainForRecovery(output)
            let outcome = await session.insert(output)
            guard self.currentSession === session else { return }
            switch outcome {
            case .inserted:
                self.discardRecoveredTranscript()
                self.playSound("Pop")
                self.resetToIdle(session: session)
            case .unverified:
                self.fail("Inserimento non verificato. Controlla il campo; se manca il testo, copialo dal menu WisperClone.", session: session)
            case .failed(let message): self.fail(message, session: session)
            }
        }
    }

    private func close(_ session: Session) {
        capture.stop()
        session.ingress?.finish()
        session.startupTask?.cancel()
        session.feedTask?.cancel()
        session.consumeTask?.cancel()
        session.finishTask?.cancel()
        session.recordingWatchdog?.cancel()
        session.startupWatchdog?.cancel()
        session.finishingWatchdog?.cancel()
        if let engine = session.engine { Task { await engine.cancel() } }
        session.engine = nil
    }

    private func cancelDictation() {
        if let session = currentSession { close(session) }
        currentSession = nil
        state = .idle
        transcript = ""
        level = 0
    }

    private func resetToIdle(session: Session) {
        guard currentSession === session else { return }
        close(session)
        currentSession = nil
        state = .idle
        transcript = ""
        level = 0
    }

    private func failIfCurrent(_ id: UUID, error: Error) {
        guard let session = currentSession, session.id == id else { return }
        // Framework errors are not logged verbatim: their payload can contain user content.
        fail((error as? TranscriptionError)?.errorDescription ?? "La dettatura locale non è riuscita. Riprova.", session: session)
    }

    private func fail(_ message: String, session: Session) {
        guard currentSession === session else { return }
        close(session)
        currentSession = nil
        transcript = ""
        level = 0
        state = .error(message)
        Log.app.error("dictation failed; visible recovery state")
    }
}
