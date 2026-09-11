import AVFoundation
import Foundation
import Testing
import WisperFormatting
@testable import WisperClone

@MainActor
private final class FakeCapture: AudioCapturing {
    var onBuffer: (@Sendable (AudioChunk) -> Void)?
    var starts = 0
    var running = false
    func start(onBuffer: @escaping @Sendable (AudioChunk) -> Void,
               onLevel: @escaping @Sendable (Float) -> Void,
               onFailure: @escaping @Sendable () -> Void) throws {
        self.onBuffer = onBuffer
        starts += 1
        running = true
    }
    func stop() { running = false; onBuffer = nil }
    func emit(_ marker: Float, rate: Double = 16000) {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160)!
        buffer.frameLength = 160 // ten milliseconds of audio
        buffer.floatChannelData![0].initialize(repeating: marker, count: 160)
        onBuffer?(AudioChunk(buffer: buffer))
    }
}

private actor FakeEngine: TranscriptionEngine {
    var started = false
    var suspended: Bool
    var releaseStart: CheckedContinuation<Void, Never>?
    var markers: [Float] = []
    let result: String
    let pair = AsyncThrowingStream<TranscriptionChunk, Error>.makeStream()
    init(suspended: Bool = false, result: String = "sì") { self.suspended = suspended; self.result = result }
    func start() async throws -> AsyncThrowingStream<TranscriptionChunk, Error> {
        started = true
        if suspended { await withCheckedContinuation { releaseStart = $0 } }
        try Task.checkCancellation()
        return pair.stream
    }
    func resume() { suspended = false; releaseStart?.resume(); releaseStart = nil }
    func preferredInputFormat() -> AVAudioFormat? { AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1) }
    func feed(_ chunk: AudioChunk) { markers.append(chunk.buffer.floatChannelData![0][0]) }
    func finish() {
        if !result.isEmpty { pair.continuation.yield(TranscriptionChunk(text: result, isFinal: true)) }
        pair.continuation.finish()
    }
    func cancel() { resume(); pair.continuation.finish() }
}

@MainActor
@Suite(.serialized)
struct DictationControllerTests {
    private func eventually(_ predicate: @MainActor () async -> Bool) async -> Bool {
        for _ in 0..<300 {
            if await predicate() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }

    @Test func capturesBeforeDelayedEngineAndPreservesRelease() async {
        let capture = FakeCapture()
        let engine = FakeEngine(suspended: true)
        var output: [String] = []
        let controller = DictationController(formatter: PassthroughFormatter(), makeEngine: { engine }, capture: capture,
            requestMicrophone: { true }, insertion: { output.append($0); return .inserted }, correct: { $0 }, playSound: { _ in })
        controller.startButtonRecording()
        #expect(await eventually { await engine.started })
        #expect(capture.running)
        capture.emit(1); capture.emit(2); capture.emit(3)
        controller.stopButtonRecording()
        #expect(!capture.running)
        #expect(controller.state == .finishing)
        await engine.resume()
        #expect(await eventually { controller.state == .idle })
        #expect(await engine.markers == [1, 2, 3])
        #expect(output == ["sì"])
        controller.deactivate()
    }

    @Test func overflowIsVisibleAndNeverInsertsPartialText() async {
        let capture = FakeCapture()
        let engine = FakeEngine(suspended: true)
        var insertions = 0
        let controller = DictationController(makeEngine: { engine }, capture: capture,
            requestMicrophone: { true }, insertion: { _ in insertions += 1; return .inserted },
            correct: { $0 }, playSound: { _ in }, audioCapacity: 2)
        controller.startButtonRecording()
        #expect(await eventually { await engine.started })
        capture.emit(1); capture.emit(2); capture.emit(3)
        #expect(await eventually { if case .error = controller.state { true } else { false } })
        #expect(controller.state.showsHUD)
        #expect(!capture.running)
        #expect(insertions == 0)
        controller.deactivate()
    }

    @Test func tenMillisecondUtteranceSurvivesAndWaitsForInsertion() async {
        let capture = FakeCapture()
        let engine = FakeEngine()
        var received = ""
        var sounds: [String] = []
        var delivery: CheckedContinuation<TextInjector.Outcome, Never>?
        let controller = DictationController(formatter: PassthroughFormatter(), makeEngine: { engine }, capture: capture,
            requestMicrophone: { true }, insertion: { text in
                received = text
                return await withCheckedContinuation { delivery = $0 }
            }, correct: { $0 }, playSound: { sounds.append($0) })
        controller.startButtonRecording()
        #expect(await eventually { capture.running })
        capture.emit(1)
        controller.stopButtonRecording()
        #expect(await eventually { delivery != nil })
        #expect(received == "sì")
        #expect(controller.state == .finishing)
        controller.startButtonRecording()
        #expect(capture.starts == 1)
        delivery?.resume(returning: .unverified)
        #expect(await eventually { if case .error = controller.state { true } else { false } })
        #expect(controller.recoverableTranscript == "sì")
        #expect(!sounds.contains("Pop"))
        controller.deactivate()
        #expect(controller.recoverableTranscript.isEmpty)
    }

    @Test func emptyCaptureDoesNotInsertAndCanRestart() async {
        let capture = FakeCapture()
        let engine = FakeEngine(result: "")
        var insertions = 0
        let controller = DictationController(makeEngine: { engine }, capture: capture,
            requestMicrophone: { true }, insertion: { _ in insertions += 1; return .inserted }, correct: { $0 }, playSound: { _ in })
        controller.startButtonRecording()
        #expect(await eventually { capture.running })
        controller.stopButtonRecording()
        #expect(await eventually { controller.state == .idle })
        #expect(insertions == 0)
        controller.deactivate()
    }

    @Test func releasingWhilePermissionPendingNeverOpensMicrophoneLater() async {
        let capture = FakeCapture()
        let engine = FakeEngine()
        var permission: CheckedContinuation<Bool, Never>?
        let controller = DictationController(makeEngine: { engine }, capture: capture,
            requestMicrophone: { await withCheckedContinuation { permission = $0 } },
            insertion: { _ in .inserted }, correct: { $0 }, playSound: { _ in })
        controller.startButtonRecording()
        #expect(await eventually { permission != nil })
        controller.stopButtonRecording()
        permission?.resume(returning: true)
        #expect(await eventually { controller.state == .idle })
        #expect(capture.starts == 0)
        controller.deactivate()
    }

    @Test func changedAudioFormatFailsInsteadOfDroppingBuffers() async {
        let capture = FakeCapture()
        let engine = FakeEngine(suspended: true)
        var insertions = 0
        let controller = DictationController(makeEngine: { engine }, capture: capture,
            requestMicrophone: { true }, insertion: { _ in insertions += 1; return .inserted }, correct: { $0 }, playSound: { _ in })
        controller.startButtonRecording()
        #expect(await eventually { await engine.started })
        capture.emit(1)
        capture.emit(2, rate: 48000)
        controller.stopButtonRecording()
        await engine.resume()
        #expect(await eventually { if case .error = controller.state { true } else { false } })
        #expect(insertions == 0)
        controller.deactivate()
    }
}
