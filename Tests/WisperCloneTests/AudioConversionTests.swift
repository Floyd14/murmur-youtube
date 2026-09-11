import AVFoundation
import Testing
@testable import WisperClone

struct AudioConversionTests {
    @Test @MainActor func audioTapCanRunOffMainActor() async throws {
        let capture = AudioCapture()
        let handler = capture.makeTapHandler()
        try await Task.detached {
            let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64))
            buffer.frameLength = 64
            buffer.floatChannelData![0].initialize(repeating: 0, count: 64)
            handler(buffer, AVAudioTime(sampleTime: 0, atRate: 48000))
        }.value
    }

    @Test func ownsAnIndependentInterleavedCopy() throws {
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: true))
        let source = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8))
        source.frameLength = 8
        source.floatChannelData![0].initialize(repeating: 0.25, count: 16)
        let copy = try #require(AudioCapture.copy(source))
        source.floatChannelData![0][15] = 0.9
        #expect(copy.floatChannelData![0][15] == 0.25)
        #expect(copy.frameLength == 8)
    }

    @Test func conversionDrainsTailAndPreservesDuration() throws {
        let input = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
        let output = try #require(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
        let converter = OrderedAudioConverter(outputFormat: output)
        var frames = 0
        for _ in 0..<10 {
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: input, frameCapacity: 480))
            buffer.frameLength = 480
            buffer.floatChannelData![0].initialize(repeating: 0.1, count: 480)
            for chunk in try converter.convert(AudioChunk(buffer: buffer)) { frames += Int(chunk.buffer.frameLength) }
        }
        for chunk in try converter.finish() { frames += Int(chunk.buffer.frameLength) }
        #expect(frames >= 1500 && frames <= 1800)
    }
}
