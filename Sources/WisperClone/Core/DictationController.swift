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

private actor CompletionRace {
    private var settled = false

    func claim() -> Bool {
        guard !settled else { return false }
        settled = true
        return true
    }
}

private func completesWithin(
    _ timeout: Duration,
    operation: @escaping @Sendable () async -> Void
) async -> Bool {
    await withCheckedContinuation { continuation in
        let race = CompletionRace()

        Task {
            await operation()
            if await race.claim() { continuation.resume(returning: true) }
        }

        Task {
            try? await Task.sleep(for: timeout)
            if await race.claim() { continuation.resume(returning: false) }
        }
    }
}

private func finishEngineWithinDeadline(_ engine: any TranscriptionEngine) async -> Bool {
    let finished = await completesWithin(.seconds(5)) {
        await engine.finish()
    }
    guard !finished else { return true }

    Log.speech.error("finalizzazione scaduta dopo 5 secondi — annullamento forzato")
    Task { await engine.cancel() }
    return false
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
                    _ = await finishEngineWithinDeadline(engine)
                    throw error
                }

                guard self.isStarting(session) else {
                    _ = await finishEngineWithinDeadline(engine)
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

        let watchdog = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(8))
            } catch {
                return
            }
            guard let self,
                  self.currentSession === session,
                  self.state == .finishing
            else { return }

            Log.speech.fault("sessione bloccata in finalizzazione — ripristino forzato")
            self.cancelDictation()
        }

        Task { @MainActor [weak self] in
            defer { watchdog.cancel() }
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

            var engineFinished = true
            if let engine = session.engine {
                engineFinished = await finishEngineWithinDeadline(engine)
            }
            session.engine = nil

            if engineFinished {
                await session.consumeTask?.value
            } else {
                session.consumeTask?.cancel()
            }
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
        Task {
            if let engine { _ = await finishEngineWithinDeadline(engine) }
        }

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
        Task {
            if let engine { _ = await finishEngineWithinDeadline(engine) }
        }

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
