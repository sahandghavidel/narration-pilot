import Foundation
import NaturalLanguage
import CryptoKit

struct SentenceAudioPiece: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var text: String
    var candidate: GuidedPreparedAudio?
    var approved = false
}

struct SentenceAudioReview: Codable, Equatable, Sendable {
    var sceneID: String
    var narration: String
    var voiceID: String
    var pieces: [SentenceAudioPiece]
    var selectedIndex: Int
    var pauseSeconds: Double = 0.22
    var assembled: GuidedPreparedAudio?
    var allApproved: Bool { !pieces.isEmpty && pieces.allSatisfy { $0.approved && $0.candidate != nil } }

    static func split(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var result: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { result.append(sentence) }
            return true
        }
        return result
    }

    static func restored(sceneID: String, narration: String, voiceID: String, previous: Self?) -> Self {
        // Keep custom split boundaries when wording has not changed. Otherwise
        // reuse unchanged sentences by occurrence, never by array position.
        if let previous, previous.sceneID == sceneID, previous.voiceID == voiceID, previous.narration == narration {
            return previous
        }
        var available = previous?.voiceID == voiceID ? previous?.pieces ?? [] : []
        let pieces = split(narration).map { text -> SentenceAudioPiece in
            if let index = available.firstIndex(where: { $0.text == text }) { return available.remove(at: index) }
            return SentenceAudioPiece(text: text)
        }
        return Self(sceneID: sceneID, narration: narration, voiceID: voiceID, pieces: pieces,
                    selectedIndex: pieces.firstIndex(where: { !$0.approved }) ?? 0,
                    pauseSeconds: previous?.pauseSeconds ?? 0.22)
    }
}

struct SentenceAudioStore {
    let directory: URL
    func url(sceneID: String, voiceID: String) -> URL {
        let hash = SHA256.hash(data: Data("\(sceneID.count):\(sceneID)\(voiceID)".utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + ".json")
    }
    func load(sceneID: String, voiceID: String) throws -> SentenceAudioReview? {
        let file = url(sceneID: sceneID, voiceID: voiceID)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(SentenceAudioReview.self, from: Data(contentsOf: file))
    }
    func save(_ review: SentenceAudioReview) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(review).write(to: url(sceneID: review.sceneID, voiceID: review.voiceID), options: .atomic)
    }
}
