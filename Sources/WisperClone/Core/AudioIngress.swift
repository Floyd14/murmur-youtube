import Foundation
import Synchronization

/// Bounded FIFO with an explicit terminal failure instead of silent audio loss.
final class AudioIngress: Sendable {
    let stream: AsyncThrowingStream<AudioChunk, Error>
    private let continuation: AsyncThrowingStream<AudioChunk, Error>.Continuation
    private struct State { var failed = false; var captured = false }
    private let state = Mutex(State())
    private let onOverflow: @Sendable () -> Void

    init(capacity: Int = 512, onOverflow: @escaping @Sendable () -> Void) {
        let pair = AsyncThrowingStream<AudioChunk, Error>.makeStream(bufferingPolicy: .bufferingOldest(capacity))
        stream = pair.stream
        continuation = pair.continuation
        self.onOverflow = onOverflow
    }

    var hasCapturedAudio: Bool { state.withLock { $0.captured } }

    func yield(_ chunk: AudioChunk) {
        guard chunk.buffer.frameLength > 0 else { return }
        let overflow = state.withLock { state -> Bool in
            guard !state.failed else { return false }
            switch continuation.yield(chunk) {
            case .enqueued: state.captured = true; return false
            case .dropped:
                state.failed = true
                continuation.finish(throwing: TranscriptionError.audioBufferOverflow)
                return true
            case .terminated: return false
            @unknown default: return false
            }
        }
        if overflow { onOverflow() }
    }

    func finish() { continuation.finish() }
}
