import CryptoKit
import Foundation

struct ClipboardWordTiming: Codable, Equatable, Sendable {
    let word: String
    let start: TimeInterval
    let end: TimeInterval
}

struct ClipboardAudioTranscription: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let model: String
    let audioSHA256: String
    let createdAt: Date
    let text: String
    let duration: TimeInterval
    let words: [ClipboardWordTiming]

    static func fingerprint(_ audio: Data) -> String {
        SHA256.hash(data: audio).map { String(format: "%02x", $0) }.joined()
    }

    var hasValidTimings: Bool {
        guard schemaVersion == 1, model == "tiny.en", duration.isFinite, duration > 0,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !words.isEmpty else { return false }
        var previousStart: TimeInterval = 0
        for word in words {
            guard !word.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  word.start.isFinite, word.end.isFinite, word.start >= previousStart,
                  word.end >= word.start, word.end <= duration + 0.5 else { return false }
            previousStart = word.start
        }
        return true
    }
}
