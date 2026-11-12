import XCTest
import AVFoundation
@testable import NarrationPilot

final class SentenceAudioTests: XCTestCase {
    static let scene7 = "Next up, take a look at this room from Riley Brown. At first, it feels like a little laptop commercial. You've got the desk, the lamp, and these close-up shots that make an everyday setup look cinematic. But there's quite a bit going on here. The laptop screen is a web page made to look like the Claude app, playing inside the 3D scene. And that little orange character is Clawd. Watch how it moves around the room. The lighting changes too, taking the scene from warm evening light through the night and into sunrise. I like how that changes the mood without needing a completely different setting. Riley says Claude wrote the code to build this in Blender and animated thirteen camera shots, including the key presses and the character's movement. For me, it's those little details that make this interesting. You're seeing a whole short film built around one room, rather than just a single render."

    func testScene7SplitAndDurableRecovery() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SentenceAudioStore(directory: root)
        var state = SentenceAudioReview.restored(sceneID: "baserow-row-1131", narration: Self.scene7, voiceID: "voice", previous: nil)
        XCTAssertEqual(state.pieces.count, 12)
        XCTAssertEqual(state.pieces.map(\.text).joined(separator: " "), Self.scene7)
        let id = UUID()
        state.pieces[0].candidate = GuidedPreparedAudio(versionID: id, duration: 3)
        state.pieces[0].approved = true
        try store.save(state)
        let loaded = try XCTUnwrap(store.load(sceneID: state.sceneID, voiceID: "voice"))
        XCTAssertEqual(loaded, state)
        let changed = Self.scene7.replacingOccurrences(of: "At first, it feels like a little laptop commercial.", with: "This looks like a laptop commercial.")
        let updated = SentenceAudioReview.restored(sceneID: state.sceneID, narration: changed, voiceID: "voice", previous: loaded)
        XCTAssertEqual(updated.pieces[0].candidate?.versionID, id)
        XCTAssertTrue(updated.pieces[0].approved)
        XCTAssertNil(updated.pieces[1].candidate)
        XCTAssertNil(SentenceAudioReview.restored(sceneID: state.sceneID, narration: changed, voiceID: "different", previous: loaded).pieces[0].candidate)
    }

    func testAbbreviationsAndDecimals() {
        let pieces = SentenceAudioReview.split("Dr. Brown tested version 5.2. It worked! Did it finish? Yes.")
        XCTAssertEqual(pieces, ["Dr. Brown tested version 5.2.", "It worked!", "Did it finish?", "Yes."])
    }

    func testAssemblyNormalizesSampleRatesAndKeepsSourceFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func fixture(_ rate: Double, _ name: String) throws -> URL {
            let url = root.appendingPathComponent(name + ".wav")
            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate))!
            buffer.frameLength = buffer.frameCapacity
            for i in 0..<Int(buffer.frameLength) { buffer.floatChannelData![0][i] = Float(sin(Double(i) * 440 * 2 * .pi / rate)) * 0.25 }
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
            return url
        }
        let a = try fixture(24000, "a"), b = try fixture(44100, "b")
        let before = try Data(contentsOf: a)
        let result = root.appendingPathComponent("joined.wav")
        let offsets = try SentenceAudioAssembler.assemble(files: [a,b], pause: 0.22, destination: result)
        XCTAssertEqual(offsets[0], 0)
        XCTAssertEqual(offsets[1], 1.22, accuracy: 0.003)
        let file = try AVAudioFile(forReading: result)
        XCTAssertEqual(Double(file.length) / file.processingFormat.sampleRate, 2.22, accuracy: 0.01)
        XCTAssertEqual(try Data(contentsOf: a), before)
    }

    @MainActor func testScene7ReviewRegenerateResumeReuseAndAssembly() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var generated: [String] = [], approvals: [String: GuidedPreparedAudio] = [:]
        var assemblies = 0
        func wire(_ review: GuidedNarrationReview) {
            review.canSpeak = { nil }
            review.speak = { _, token in review.speechFinished(token) }
            review.selectedAudioVoice = { GuidedAudioVoice(id: "test-voice", name: "Test") }
            review.prepareAudio = { text, _, _, current in
                XCTAssertTrue(current()); generated.append(text)
                return GuidedPreparedAudio(versionID: UUID(), duration: 2)
            }
            review.previewAudio = { _, current in XCTAssertTrue(current()) }
            review.approvedSentence = { text, _ in approvals[text] }
            review.approveAudioVersion = { id, text, _ in approvals[text] = GuidedPreparedAudio(versionID: id, duration: 2) }
            review.assembleAudio = { _, _, pieces, _, current in
                XCTAssertTrue(current()); XCTAssertEqual(pieces.count, 12); assemblies += 1
                return GuidedPreparedAudio(versionID: UUID(), duration: 26.42)
            }
        }
        func wait(_ review: GuidedNarrationReview, _ phase: String) async throws {
            for _ in 0..<200 { if review.phase == phase && !review.audioBusy { return }; try await Task.sleep(for: .milliseconds(10)) }
            XCTFail("Expected \(phase), got \(review.phase): \(review.message)")
            throw NSError(domain: "TestTimeout", code: 1)
        }
        let review = GuidedNarrationReview(directory: root)
        wire(review)
        try await review.beginChapter([GuidedNarrationDraft(sessionID: UUID(), sceneID: "baserow-row-1131", revision: 1, narration: Self.scene7)])
        review.approveWording()
        try await wait(review, "sentenceReady")
        XCTAssertEqual(generated.count, 1)
        XCTAssertNil(review.audioDecision)
        review.recordMyself(); review.startAgentPractice()
        XCTAssertNil(review.audioDecision, "Partial sentences cannot record or practice")
        let original = review.currentSentence!.candidate!.versionID
        review.approveSentence()
        try await wait(review, "sentenceReady")
        review.generateAudio(forceNewVersion: true)
        try await wait(review, "sentenceReady")
        XCTAssertEqual(review.sentences!.pieces[0].candidate!.versionID, original)
        XCTAssertEqual(generated.count, 3)
        review.stop()
        let restored = GuidedNarrationReview(directory: root)
        wire(restored)
        XCTAssertEqual(restored.sentences!.pieces[0].candidate!.versionID, original)
        XCTAssertTrue(restored.sentences!.pieces[0].approved)
        restored.replayAudio()
        try await wait(restored, "sentenceReady")
        XCTAssertEqual(generated.count, 3, "Restart must replay the saved candidate without generation")
        for _ in 1..<12 {
            restored.approveSentence()
            try await wait(restored, restored.sentences!.allApproved ? "audioReady" : "sentenceReady")
        }
        XCTAssertEqual(assemblies, 1)
        XCTAssertEqual(generated.count, 13)
        XCTAssertTrue(restored.sentences!.allApproved)
        restored.end()
        // An independent scene uses the global approved sentence cache.
        let other = GuidedNarrationReview(directory: root.appendingPathComponent("other"))
        wire(other)
        try await other.beginChapter([GuidedNarrationDraft(sessionID: UUID(), sceneID: "different-scene", revision: 1, narration: Self.scene7)])
        other.approveWording()
        try await wait(other, "audioReady")
        XCTAssertEqual(generated.count, 13, "Approved sentences must be reusable across scenes")
        XCTAssertEqual(assemblies, 2)
        other.end()
    }
}
