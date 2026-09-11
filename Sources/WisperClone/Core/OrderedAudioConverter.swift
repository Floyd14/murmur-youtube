import AVFoundation
import Foundation
import Synchronization

/// Confined to one feed task. Never invoked on the real-time capture callback.
final class OrderedAudioConverter {
    private let outputFormat: AVAudioFormat
    private var inputFormat: AVAudioFormat?
    private var converter: AVAudioConverter?

    init(outputFormat: AVAudioFormat) { self.outputFormat = outputFormat }

    func convert(_ chunk: AudioChunk) throws -> [AudioChunk] {
        let buffer = chunk.buffer
        if let inputFormat, inputFormat != buffer.format { throw TranscriptionError.audioConversionFailed }
        if inputFormat == nil {
            inputFormat = buffer.format
            if buffer.format != outputFormat {
                guard let converter = AVAudioConverter(from: buffer.format, to: outputFormat) else {
                    throw TranscriptionError.audioConversionFailed
                }
                self.converter = converter
            }
        }
        guard let converter else { return [chunk] }
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * outputFormat.sampleRate / buffer.format.sampleRate)) + 256
        let supplied = Mutex(false)
        return try drain(converter, capacity: capacity) { _, status in
            let first = supplied.withLock { value in
                defer { value = true }
                return !value
            }
            guard first else { status.pointee = .noDataNow; return nil }
            status.pointee = .haveData
            return chunk.buffer
        }
    }

    func finish() throws -> [AudioChunk] {
        guard let converter else { return [] }
        return try drain(converter, capacity: 4096) { _, status in
            status.pointee = .endOfStream
            return nil
        }
    }

    private func drain(_ converter: AVAudioConverter, capacity: AVAudioFrameCount,
                       input: @escaping AVAudioConverterInputBlock) throws -> [AudioChunk] {
        var result: [AudioChunk] = []
        while true {
            guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
                throw TranscriptionError.audioConversionFailed
            }
            var error: NSError?
            let status = converter.convert(to: output, error: &error, withInputFrom: input)
            guard error == nil, status != .error else { throw TranscriptionError.audioConversionFailed }
            if output.frameLength > 0 { result.append(AudioChunk(buffer: output)) }
            switch status {
            case .haveData:
                guard output.frameLength > 0 else { throw TranscriptionError.audioConversionFailed }
            case .inputRanDry, .endOfStream: return result
            case .error: throw TranscriptionError.audioConversionFailed
            @unknown default: throw TranscriptionError.audioConversionFailed
            }
        }
    }
}
