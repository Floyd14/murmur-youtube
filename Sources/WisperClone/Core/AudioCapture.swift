import AVFoundation
import Foundation
import Synchronization

/// Cattura il microfono e converte ogni buffer nel formato richiesto dal motore STT.
final class AudioCapture: @unchecked Sendable {
    private struct CallbackState: ~Copyable {
        var converter: AVAudioConverter?
        var outputFormat: AVAudioFormat?
        var onBuffer: (@Sendable (AudioChunk) -> Void)?
        var onLevel: (@Sendable (Float) -> Void)?
    }

    private let engine = AVAudioEngine()
    private let callbackState = Mutex(
        CallbackState(converter: nil, outputFormat: nil, onBuffer: nil, onLevel: nil)
    )
    private var isRunning = false

    func start(
        outputFormat: AVAudioFormat,
        onBuffer: @escaping @Sendable (AudioChunk) -> Void,
        onLevel: @escaping @Sendable (Float) -> Void
    ) throws {
        guard !isRunning else { return }

        let input = engine.inputNode
        let nativeFormat = input.outputFormat(forBus: 0)
        let converter = nativeFormat == outputFormat
            ? nil
            : AVAudioConverter(from: nativeFormat, to: outputFormat)

        callbackState.withLock { state in
            state.converter = converter
            state.outputFormat = outputFormat
            state.onBuffer = onBuffer
            state.onLevel = onLevel
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: nativeFormat) { [weak self] buffer, _ in
            self?.handle(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
            isRunning = true
        } catch {
            input.removeTap(onBus: 0)
            engine.stop()
            clearCallbackState()
            throw error
        }

        Log.audio.info("capture started — native \(nativeFormat.sampleRate)Hz → engine \(outputFormat.sampleRate)Hz")
    }

    func stop() {
        guard isRunning else {
            clearCallbackState()
            return
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        clearCallbackState()
        Log.audio.info("capture stopped")
    }

    private func clearCallbackState() {
        callbackState.withLock { state in
            state.converter = nil
            state.outputFormat = nil
            state.onBuffer = nil
            state.onLevel = nil
        }
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        callbackState.withLock { state in
            state.onLevel?(Self.rms(of: buffer))
            guard let outputFormat = state.outputFormat else { return }

            guard let converter = state.converter else {
                if let copy = Self.copy(buffer) {
                    state.onBuffer?(AudioChunk(buffer: copy))
                }
                return
            }

            let ratio = outputFormat.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
            guard let converted = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: capacity
            ) else { return }

            nonisolated(unsafe) let input = buffer
            let consumed = Latch()
            var error: NSError?
            let status = converter.convert(to: converted, error: &error) { _, outStatus in
                guard !consumed.take() else {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                outStatus.pointee = .haveData
                return input
            }

            if let error {
                Log.audio.error("conversion failed: \(error.localizedDescription)")
                return
            }
            guard status != .error, converted.frameLength > 0 else { return }
            state.onBuffer?(AudioChunk(buffer: converted))
        }
    }

    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard buffer.frameLength > 0,
              let copy = AVAudioPCMBuffer(
                pcmFormat: buffer.format,
                frameCapacity: buffer.frameLength
              )
        else { return nil }

        copy.frameLength = buffer.frameLength
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)

        if let source = buffer.floatChannelData, let destination = copy.floatChannelData {
            for channel in 0..<channels {
                destination[channel].update(from: source[channel], count: frames)
            }
        } else if let source = buffer.int16ChannelData, let destination = copy.int16ChannelData {
            for channel in 0..<channels {
                destination[channel].update(from: source[channel], count: frames)
            }
        } else if let source = buffer.int32ChannelData, let destination = copy.int32ChannelData {
            for channel in 0..<channels {
                destination[channel].update(from: source[channel], count: frames)
            }
        } else {
            return nil
        }

        return copy
    }

    private final class Latch: @unchecked Sendable {
        private var fired = false

        func take() -> Bool {
            defer { fired = true }
            return fired
        }
    }

    private static func rms(of buffer: AVAudioPCMBuffer) -> Float {
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
