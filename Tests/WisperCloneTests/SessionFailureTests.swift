import AVFoundation
import Testing
import WisperFormatting
@testable import WisperClone

@MainActor
private final class SessionFailureCapture: AudioCapturing {
    private(set) var starts = 0
    private(set) var running = false
    private var onBuffer: (@Sendable (AudioChunk) -> Void)?

    func start(onBuffer: @escaping @Sendable (AudioChunk) -> Void,
               onLevel: @escaping @Sendable (Float) -> Void,
               onFailure: @escaping @Sendable () -> Void) throws {
        self.onBuffer = onBuffer
        starts += 1
        running = true
    }

    func stop() {
        running = false
        onBuffer = nil
    }

    func emitAudio() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160)!
        buffer.frameLength = 160
        buffer.floatChannelData![0].initialize(repeating: 0.1, count: 160)
        onBuffer?(AudioChunk(buffer: buffer))
    }
}

private actor SessionFailureEngine: TranscriptionEngine {
    private let result: String
    private let blocksStart: Bool
    private let blocksFinish: Bool
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var finishContinuation: CheckedContinuation<Void, Never>?
    private let pair = AsyncThrowingStream<TranscriptionChunk, Error>.makeStream()
    private var didStart = false

    init(result: String = "test", blocksStart: Bool = false, blocksFinish: Bool = false) {
        self.result = result
        self.blocksStart = blocksStart
        self.blocksFinish = blocksFinish
    }

    func start() async throws -> AsyncThrowingStream<TranscriptionChunk, Error> {
        didStart = true
        if blocksStart { await withCheckedContinuation { startContinuation = $0 } }
        try Task.checkCancellation()
        return pair.stream
    }

    func preferredInputFormat() -> AVAudioFormat? {
        AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)
    }

    func feed(_ chunk: AudioChunk) {}

    func finish() async throws {
        if blocksFinish { await withCheckedContinuation { finishContinuation = $0 } }
        try Task.checkCancellation()
        pair.continuation.yield(TranscriptionChunk(text: result, isFinal: true))
        pair.continuation.finish()
    }

    func cancel() {
        startContinuation?.resume()
        startContinuation = nil
        finishContinuation?.resume()
        finishContinuation = nil
        pair.continuation.finish()
    }

    func started() -> Bool { didStart }
}

@MainActor
@Suite(.serialized)
struct SessionFailureTests {
    private func eventually(_ predicate: @MainActor () async -> Bool) async -> Bool {
        for _ in 0..<300 {
            if await predicate() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }

    @Test("a finalization timeout aborts the session without inserting partial text")
    func finalizationTimeoutCancelsSession() async {
        let capture = SessionFailureCapture()
        let engine = SessionFailureEngine(blocksFinish: true)
        var insertions = 0
        let controller = DictationController(
            formatter: PassthroughFormatter(), makeEngine: { engine }, capture: capture,
            requestMicrophone: { true }, insertion: { _ in insertions += 1; return .inserted },
            correct: { $0 }, playSound: { _ in }, finishingTimeout: .milliseconds(40)
        )

        controller.startButtonRecording()
        #expect(await eventually { await engine.started() && capture.running })
        capture.emitAudio()
        controller.stopButtonRecording()

        #expect(await eventually { if case .error = controller.state { true } else { false } })
        #expect(!capture.running)
        #expect(insertions == 0)
        controller.deactivate()
    }

    @Test("deactivation cancels a starting engine and a later session can record")
    func deactivationDuringEngineStartupDoesNotLeakIntoNextSession() async {
        let capture = SessionFailureCapture()
        let delayed = SessionFailureEngine(blocksStart: true)
        let next = SessionFailureEngine()
        var engines = [delayed, next]
        let controller = DictationController(
            makeEngine: { engines.removeFirst() }, capture: capture, requestMicrophone: { true },
            insertion: { _ in .inserted }, correct: { $0 }, playSound: { _ in }
        )

        controller.startButtonRecording()
        #expect(await eventually { await delayed.started() && capture.running })
        controller.deactivate()
        #expect(controller.state == .idle)
        #expect(!capture.running)

        controller.startButtonRecording()
        #expect(await eventually { capture.starts == 2 && capture.running })
        #expect(controller.state == .listening)
        controller.deactivate()
    }

    @Test("a stale insertion completion cannot terminate a newer recording")
    func staleInsertionCompletionDoesNotTouchNextSession() async {
        let capture = SessionFailureCapture()
        let first = SessionFailureEngine(result: "prima")
        let second = SessionFailureEngine(result: "seconda")
        var engines = [first, second]
        var firstInsertion: CheckedContinuation<TextInjector.Outcome, Never>?
        let controller = DictationController(
            formatter: PassthroughFormatter(), makeEngine: { engines.removeFirst() }, capture: capture,
            requestMicrophone: { true }, insertion: { text in
                if text == "prima" {
                    return await withCheckedContinuation { firstInsertion = $0 }
                }
                return .inserted
            }, correct: { $0 }, playSound: { _ in }
        )

        controller.startButtonRecording()
        #expect(await eventually { await first.started() && capture.running })
        capture.emitAudio()
        controller.stopButtonRecording()
        #expect(await eventually { firstInsertion != nil })
        controller.deactivate()

        controller.startButtonRecording()
        #expect(await eventually { await second.started() && capture.running })
        #expect(controller.state == .listening)
        firstInsertion?.resume(returning: .inserted)
        #expect(await eventually { controller.state == .listening })
        #expect(capture.starts == 2)
        controller.deactivate()
    }
}
