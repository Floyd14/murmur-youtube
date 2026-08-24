import WisperDictionary
import WisperFormatting
import AppKit
import Foundation
import Observation

@Sendable
func engineForCurrentSetting() -> any TranscriptionEngine {
    MainActor.assumeIsolated {
        AppleSpeechEngine(locale: Settings.shared.recognitionLanguage.locale)
    }
}

@MainActor
@Observable
final class DictationController {
    enum State: Equatable {
        case idle
        case starting
        case listening
        case finishing
        case error(String)

        var isActive: Bool {
            switch self {
            case .starting, .listening, .finishing: true
            case .idle, .error: false
            }
        }
    }

    private final class Session {
        var startupTask: Task<Void, Never>?
        var engine: (any TranscriptionEngine)?
        var consumeTask: Task<Void, Never>?
        var feedTask: Task<Void, Never>?
        var audioContinuation: AsyncStream<AudioChunk>.Continuation?
    }

    private(set) var state: State = .idle
    private(set) var transcript = ""
    private(set) var level: Float = 0

    private let hotkey = HotkeyMonitor()
    private let capture = AudioCapture()
    private let makeEngine: @Sendable () -> any TranscriptionEngine
    private let formatter: (any TextFormatter)?
    private var currentSession: Session?

    init(
        formatter: (any TextFormatter)? = nil,
        makeEngine: @escaping @Sendable () -> any TranscriptionEngine = engineForCurrentSetting
    ) {
        self.formatter = formatter
        self.makeEngine = makeEngine
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
    }

    @discardableResult
    func reloadHotkey() -> Bool {
        hotkey.stop()
        return activate()
    }

    func startButtonRecording() {
        beginDictation()
    }

    func stopButtonRecording() {
        endDictation()
    }

    private func beginDictation() {
        guard case .idle = state else { return }

        let session = Session()
        currentSession = session
        state = .starting
        transcript = ""

        session.startupTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                guard await Permissions.requestMicrophone() else {
                    self.fail(
                        "Accesso al microfono disattivato. Abilitalo in Impostazioni di Sistema.",
                        session: session
                    )
                    return
                }
                guard self.isStarting(session) else { return }

                let engine = self.makeEngine()
                let chunks: AsyncThrowingStream<TranscriptionChunk, Error>
                do {
                    chunks = try await engine.start()
                } catch {
                    await engine.finish()
                    throw error
                }

                guard self.isStarting(session) else {
                    await engine.finish()
                    return
                }
                session.engine = engine

                guard let format = await engine.preferredInputFormat() else {
                    throw TranscriptionError.noAudioFormat
                }
                guard self.isStarting(session) else { return }

                let (audioStream, continuation) = AsyncStream<AudioChunk>.makeStream(
                    bufferingPolicy: .bufferingNewest(64)
                )
                session.audioContinuation = continuation
                session.feedTask = Task.detached(priority: .userInitiated) {
                    for await chunk in audioStream {
                        await engine.feed(chunk)
                    }
                }

                try self.capture.start(
                    outputFormat: format,
                    onBuffer: { continuation.yield($0) },
                    onLevel: { [weak self] level in
                        Task { @MainActor in self?.updateLevel(level) }
                    }
                )

                guard self.isStarting(session) else { return }
                self.state = .listening
                if Settings.shared.soundEnabled { NSSound(named: "Tink")?.play() }

                session.consumeTask = Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        for try await chunk in chunks {
                            guard self.currentSession === session else { return }
                            self.transcript = chunk.text
                        }
                    } catch {
                        self.fail(error.localizedDescription, session: session)
                    }
                }
            } catch {
                self.fail(error.localizedDescription, session: session)
            }
        }
    }

    private func endDictation() {
        guard state.isActive, state != .finishing, let session = currentSession else { return }
        state = .finishing
        capture.stop()
        level = 0

        Task { @MainActor [weak self] in
            guard let self else { return }

            // Se il tasto viene rilasciato durante permessi o caricamento modello, aspetta
            // che l'avvio esca senza rendere disponibile una nuova sessione concorrente.
            await session.startupTask?.value
            guard self.currentSession === session else { return }

            self.capture.stop()
            session.audioContinuation?.finish()
            session.audioContinuation = nil
            await session.feedTask?.value
            session.feedTask = nil

            await session.engine?.finish()
            session.engine = nil
            await session.consumeTask?.value
            session.consumeTask = nil

            guard self.currentSession === session else { return }

            let raw = self.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else {
                self.resetToIdle(session: session)
                return
            }

            let selectedFormatter: any TextFormatter
            if let formatter = self.formatter {
                selectedFormatter = formatter
            } else if Settings.shared.smartCleanup {
                selectedFormatter = FoundationModelFormatter()
            } else {
                selectedFormatter = RuleBasedFormatter()
            }

            let cleaned = Settings.shared.cleanupEnabled
                ? await selectedFormatter.format(raw)
                : raw
            let (output, corrections) = DictionaryStore.shared.corrector.apply(to: cleaned)

            if !corrections.isEmpty {
                Log.speech.info("dictionary · \(corrections.count, privacy: .public) correzione/i")
            }

            TextInjector.insert(output)
            if Settings.shared.soundEnabled { NSSound(named: "Pop")?.play() }
            self.resetToIdle(session: session)
        }
    }

    private func cancelDictation() {
        guard let session = currentSession else {
            state = .idle
            transcript = ""
            level = 0
            return
        }

        currentSession = nil
        capture.stop()
        session.audioContinuation?.finish()
        session.audioContinuation = nil
        session.startupTask?.cancel()
        session.feedTask?.cancel()
        session.consumeTask?.cancel()

        let engine = session.engine
        session.engine = nil
        Task { await engine?.finish() }

        state = .idle
        transcript = ""
        level = 0
    }

    private func isStarting(_ session: Session) -> Bool {
        guard currentSession === session else { return false }
        if case .starting = state { return true }
        return false
    }

    private func updateLevel(_ new: Float) {
        level += (new - level) * 0.35
    }

    private func resetToIdle(session: Session) {
        guard currentSession === session else { return }
        currentSession = nil
        state = .idle
        transcript = ""
        level = 0
    }

    private func fail(_ message: String, session: Session) {
        guard currentSession === session else { return }

        Log.app.error("\(message, privacy: .public)")
        currentSession = nil
        capture.stop()
        session.audioContinuation?.finish()
        session.audioContinuation = nil
        session.feedTask?.cancel()
        session.consumeTask?.cancel()

        let engine = session.engine
        session.engine = nil
        Task { await engine?.finish() }

        state = .error(message)
        level = 0

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self else { return }
            if case .error = self.state {
                self.state = .idle
                self.transcript = ""
            }
        }
    }
}
