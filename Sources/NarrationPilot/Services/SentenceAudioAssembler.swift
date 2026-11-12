import AVFoundation
import Foundation

struct SentenceAssemblyPart: Codable, Sendable {
    var takeID: UUID
    var start: Double
}
struct SentenceAssemblySource: Codable, Sendable {
    var sentenceAssembly: [SentenceAssemblyPart]
}

enum SentenceAudioAssembler {
    static func assemble(files: [URL], pause: Double, destination: URL) throws -> [Double] {
        guard !files.isEmpty, pause.isFinite, (0...2).contains(pause) else { throw failure("Invalid sentence assembly.") }
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24000, channels: 1, interleaved: false)!
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 24000,
                                      AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                                      AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        let output = try AVAudioFile(forWriting: destination, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        var starts: [Double] = []
        var writtenFrames: AVAudioFramePosition = 0
        for (index, url) in files.enumerated() {
            try Task.checkCancellation()
            let input = try AVAudioFile(forReading: url)
            guard input.length > 0, input.length < 24000 * 600 else { throw failure("Invalid sentence audio length.") }
            let source = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: AVAudioFrameCount(input.length))!
            // AVAudioFile can return a short read before EOF. Accumulate every
            // frame so the final syllable is never silently dropped.
            while AVAudioFramePosition(source.frameLength) < input.length {
                let remaining = AVAudioFrameCount(input.length) - source.frameLength
                let chunk = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: remaining)!
                try input.read(into: chunk, frameCount: remaining)
                guard chunk.frameLength > 0, let destination = source.floatChannelData, let data = chunk.floatChannelData else {
                    throw failure("Could not read the complete sentence audio.")
                }
                for channel in 0..<Int(input.processingFormat.channelCount) {
                    destination[channel].advanced(by: Int(source.frameLength)).update(from: data[channel], count: Int(chunk.frameLength))
                }
                source.frameLength += chunk.frameLength
            }
            guard let converter = AVAudioConverter(from: input.processingFormat, to: format) else { throw failure("Cannot convert sentence audio.") }
            converter.primeMethod = .none
            let capacity = AVAudioFrameCount(ceil(Double(source.frameLength) * 24000 / input.processingFormat.sampleRate)) + 1024
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity)!
            let provider = SentencePCMInput(source)
            var conversionError: NSError?
            let status = converter.convert(to: buffer, error: &conversionError) { _, state in
                let next = provider.consume()
                state.pointee = next == nil ? .endOfStream : .haveData
                return next
            }
            guard status != .error, conversionError == nil, buffer.frameLength > 0 else { throw conversionError ?? failure("Sentence conversion failed.") }
            // A 3ms edge fade prevents clicks without deleting any spoken samples.
            let length = Int(buffer.frameLength), fade = min(72, length / 2)
            if let samples = buffer.floatChannelData?[0], fade > 0 {
                for i in 0..<fade {
                    let gain = Float(i) / Float(fade)
                    samples[i] *= gain; samples[length - 1 - i] *= gain
                }
            }
            starts.append(Double(writtenFrames) / 24000)
            try output.write(from: buffer)
            writtenFrames += AVAudioFramePosition(buffer.frameLength)
            if index < files.count - 1, pause > 0 {
                let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount((pause * 24000).rounded()))!
                silence.frameLength = silence.frameCapacity
                if let data = silence.floatChannelData?[0] { data.initialize(repeating: 0, count: Int(silence.frameLength)) }
                try output.write(from: silence)
                writtenFrames += AVAudioFramePosition(silence.frameLength)
            }
        }
        return starts
    }
    private static func failure(_ message: String) -> NSError { NSError(domain: "SentenceAudio", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

// AVAudioConverter may invoke its input callback on an internal thread.
private final class SentencePCMInput: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: AVAudioPCMBuffer?
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    func consume() -> AVAudioPCMBuffer? {
        lock.lock(); defer { lock.unlock() }
        let next = buffer; buffer = nil; return next
    }
}
