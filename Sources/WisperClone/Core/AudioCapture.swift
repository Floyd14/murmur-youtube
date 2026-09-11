import AVFoundation
import Foundation
import Synchronization

@MainActor
protocol AudioCapturing: AnyObject {
    func start(onBuffer: @escaping @Sendable (AudioChunk) -> Void,
               onLevel: @escaping @Sendable (Float) -> Void,
               onFailure: @escaping @Sendable () -> Void) throws
    func stop()
}

/// The callback copies borrowed native buffers. Conversion runs on the ordered drain.
final class AudioCapture: AudioCapturing, @unchecked Sendable {
    private struct CallbackState: ~Copyable {
        var onBuffer: (@Sendable (AudioChunk) -> Void)?
        var onLevel: (@Sendable (Float) -> Void)?
        var onFailure: (@Sendable () -> Void)?
    }
    private let engine = AVAudioEngine()
    private let callbackState = Mutex(CallbackState())
    private var isRunning = false

    func start(onBuffer: @escaping @Sendable (AudioChunk) -> Void,
               onLevel: @escaping @Sendable (Float) -> Void,
               onFailure: @escaping @Sendable () -> Void) throws {
        guard !isRunning else { return }
        let input = engine.inputNode
        let nativeFormat = input.outputFormat(forBus: 0)
        guard nativeFormat.sampleRate > 0, nativeFormat.channelCount > 0 else {
            throw TranscriptionError.noAudioFormat
        }
        callbackState.withLock { state in
            state.onBuffer = onBuffer
            state.onLevel = onLevel
            state.onFailure = onFailure
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: nativeFormat, block: makeTapHandler())
        engine.prepare()
        do {
            try engine.start()
            isRunning = true
        } catch {
            input.removeTap(onBus: 0)
            engine.stop()
            clearCallbackState()
            throw TranscriptionError.captureFailed
        }
        Log.audio.info("native capture started")
    }

    func stop() {
        if isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            isRunning = false
        }
        // Synchronize with the last callback before closing the ingress stream.
        clearCallbackState()
    }

    private nonisolated func clearCallbackState() {
        callbackState.withLock { state in
            state.onBuffer = nil
            state.onLevel = nil
            state.onFailure = nil
        }
    }

    // AVFAudio invokes this on its service queue. Creating the closure inside the
    // MainActor-isolated start() inherits that actor and traps on the first buffer.
    // Both the creation context and function type must permit off-main execution.
    nonisolated func makeTapHandler() -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { [weak self] buffer, _ in self?.handle(buffer) }
    }

    private nonisolated func handle(_ buffer: AVAudioPCMBuffer) {
        callbackState.withLock { state in
            guard state.onBuffer != nil, buffer.frameLength > 0 else { return }
            guard let copy = Self.copy(buffer) else { state.onFailure?(); return }
            state.onLevel?(Self.rms(of: buffer))
            state.onBuffer?(AudioChunk(buffer: copy))
        }
    }

    nonisolated static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard buffer.frameLength > 0,
              let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength)
        else { return nil }
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        guard source.count == destination.count else { return nil }
        // AudioBufferList also handles interleaved multichannel input correctly.
        for index in source.indices {
            guard let from = source[index].mData, let to = destination[index].mData,
                  destination[index].mDataByteSize >= source[index].mDataByteSize else { return nil }
            memcpy(to, from, Int(source[index].mDataByteSize))
        }
        return copy
    }

    private nonisolated static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }

        var sum: Float = 0
        for index in 0..<count {
            let sample = channel[index]
            sum += sample * sample
        }
        let rms = (sum / Float(count)).squareRoot()
        let decibels = 20 * log10(max(rms, 1e-7))
        return max(0, min(1, (decibels + 50) / 50))
    }
}
