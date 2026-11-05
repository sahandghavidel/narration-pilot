import Foundation

@MainActor private final class GenerationSwitch { var fails = false }

@main
struct GuidedAudioReviewCheck {
    @MainActor static func main() async throws {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--bridge" {
            let bridge = GuidedNarrationReview(directory: URL(fileURLWithPath: CommandLine.arguments[2]))
            bridge.canSpeak = { nil }; bridge.speak = { _, token in bridge.speechFinished(token) }
            bridge.selectedAudioVoice = { GuidedAudioVoice(id: "fixture-voice", name: "Fixture voice") }
            bridge.prepareAudio = { _, _, _, _ in GuidedPreparedAudio(versionID: UUID(), duration: 4.6) }
            bridge.previewAudio = { _, _ in }
            bridge.approveAudioVersion = { _, _, _ in }
            bridge.start()
            for _ in 0..<600 {
                await bridge.processInbox()
                if bridge.phase == "awaitingDecision" { bridge.approve() }
                if bridge.phase == "audioReady", !bridge.audioBusy {
                    if bridge.audioReview?.attempt == 1 { bridge.improve() } else { bridge.approve() }
                }
                if !bridge.active && bridge.draft != nil { bridge.stop(); return }
                try await Task.sleep(for: .milliseconds(50))
            }
            bridge.stop(); throw NSError(domain: "BridgeCheck", code: 1)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("guided-audio-check-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let review = GuidedNarrationReview(directory: root)
        var voice = GuidedAudioVoice(id: "voice-a", name: "Voice A")
        var prepared: [(String, String, Bool)] = []
        var previews: [UUID] = [], approvals: [UUID] = []
        var stopped: [UUID] = []
        let generationSwitch = GenerationSwitch()
        let firstAudio = UUID(), secondAudio = UUID()
        review.canSpeak = { nil }
        review.speak = { _, token in review.speechFinished(token) }
        review.selectedAudioVoice = { voice }
        review.prepareAudio = { text, voiceID, force, isCurrent in
            precondition(isCurrent())
            prepared.append((text, voiceID, force))
            try await Task.sleep(for: .milliseconds(20))
            if generationSwitch.fails { throw NSError(domain: "FixtureGeneration", code: 1) }
            return GuidedPreparedAudio(versionID: force ? secondAudio : firstAudio, duration: 4.6)
        }
        review.previewAudio = { audio, isCurrent in precondition(isCurrent()); previews.append(audio.versionID) }
        review.approveAudioVersion = { id, text, voiceID in
            precondition(id == previews.last && text == review.draft?.narration && voiceID == "voice-a")
            approvals.append(id)
        }
        review.stopAudioPreview = { if let id = $0 { stopped.append(id) } }
        func send(_ kind: String, draft: GuidedNarrationDraft, eventID: UUID? = nil) async throws {
            let c = GuidedNarrationCommand(id: UUID(), sessionID: draft.sessionID, kind: kind, draft: kind == "submit" ? draft : nil, eventID: eventID)
            try GuidedNarrationReview.encoder().encode(c).write(to: root.appendingPathComponent("commands/\(c.id.uuidString).json"), options: .atomic)
            await review.processInbox()
            let r = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("receipts/\(c.id.uuidString).json"))) as! [String: Any]
            precondition(r["accepted"] as? Bool == true, r.description)
        }
        func waitFor(_ condition: @MainActor () -> Bool) async throws {
            for _ in 0..<200 { if condition() { return }; try await Task.sleep(for: .milliseconds(5)) }
            preconditionFailure("Timed out waiting for guided audio stage: \(review.phase)")
        }
        let draft = GuidedNarrationDraft(sessionID: UUID(), sceneID: "fixture-scene", revision: 1, narration: "Let's add twelve and eight.")
        try await send("submit", draft: draft)
        precondition(review.phase == "awaitingDecision")
        review.approve()
        let wordingEvent = review.decision!
        precondition(wordingEvent.kind == "approveNarration" && review.audioBusy)
        voice = GuidedAudioVoice(id: "voice-b", name: "Voice B") // Must not affect the frozen voice.
        review.approve(); review.improve(); review.approve()
        try await send("acknowledge", draft: draft, eventID: wordingEvent.id)
        precondition(review.phase != "approved", "Wording acknowledgment must not overwrite the live audio stage")
        try await waitFor { review.phase == "audioReady" && !review.audioBusy }
        precondition(prepared.count == 1 && prepared[0].0 == draft.narration && prepared[0].1 == "voice-a" && !prepared[0].2)
        precondition(review.audioReview?.versionID == firstAudio && previews == [firstAudio])
        // G in audio review regenerates; it must not request improved wording.
        review.improve(); review.improve(); review.approve()
        try await waitFor { review.phase == "audioReady" && !review.audioBusy }
        precondition(prepared.count == 2 && prepared[1].1 == "voice-a" && prepared[1].2)
        precondition(review.decision?.id == wordingEvent.id && review.audioReview?.attempt == 2)
        precondition(stopped.contains(firstAudio) && previews == [firstAudio, secondAudio])
        let restoredCandidate = GuidedNarrationReview(directory: root)
        precondition(restoredCandidate.phase == "audioSuspended" && restoredCandidate.audioReview?.versionID == secondAudio)
        precondition(prepared.count == 2 && previews.count == 2, "Restore must not generate or autoplay")
        review.approve(); let audioEvent = review.audioDecision!
        precondition(review.phase == "audioApproved" && approvals == [secondAudio])
        precondition(audioEvent.kind == "approveAudio" && audioEvent.draft == draft && audioEvent.audio.versionID == secondAudio)
        review.approve(); review.improve()
        precondition(approvals.count == 1 && prepared.count == 2)
        try await send("acknowledge", draft: draft, eventID: audioEvent.id)
        precondition(review.audioAcknowledged)
        let restoredApproval = GuidedNarrationReview(directory: root)
        precondition(restoredApproval.phase == "audioApproved" && restoredApproval.audioDecision?.id == audioEvent.id && restoredApproval.audioAcknowledged)
        review.end()
        precondition(!review.approve() && !review.improve(), "Ending guided review restores standalone shortcut ownership")

        // Generation failure keeps approved wording and allows G to retry.
        voice = GuidedAudioVoice(id: "voice-a", name: "Voice A")
        var failureDraft = draft; failureDraft.sessionID = UUID()
        generationSwitch.fails = true
        try await send("submit", draft: failureDraft); review.approve()
        try await waitFor { review.phase == "audioFailed" && !review.audioBusy }
        precondition(review.decision?.draft == failureDraft && review.audioDecision == nil)
        review.approve(); precondition(review.audioDecision == nil)
        generationSwitch.fails = false; review.improve()
        try await waitFor { review.phase == "audioReady" && !review.audioBusy }
        precondition(prepared.last!.2 && review.audioReview?.voice.id == "voice-a")
        // Preview failure cannot be treated as a heard/approvable candidate.
        review.previewAudio = { _, _ in throw NSError(domain: "FixturePreview", code: 1) }
        review.replayAudio()
        try await waitFor { review.phase == "audioFailed" && !review.audioBusy }
        review.approve(); precondition(review.audioDecision == nil)
        review.end()

        // Ending a review while its generation is in flight suppresses late playback.
        var pending: CheckedContinuation<GuidedPreparedAudio, Never>?
        review.prepareAudio = { _, _, _, _ in await withCheckedContinuation { pending = $0 } }
        review.previewAudio = { audio, _ in previews.append(audio.versionID) }
        var cancelled = draft; cancelled.sessionID = UUID()
        try await send("submit", draft: cancelled); review.approve()
        try await waitFor { pending != nil }
        let beforeLate = previews.count
        review.end(); pending?.resume(returning: GuidedPreparedAudio(versionID: UUID(), duration: 4.6))
        try await Task.sleep(for: .milliseconds(50))
        precondition(!review.active && !review.audioBusy && previews.count == beforeLate)
        precondition(!FileManager.default.fileExists(atPath: root.appendingPathComponent("audio-events/\(cancelled.sessionID.uuidString.lowercased())-r1.json").path))
        // A chapter owns its own cursor. A failed manual take and duplicate M cannot skip a row.
        let chapter = ["First scene.", "Second scene."].enumerated().map {
            GuidedNarrationDraft(sessionID: UUID(), sceneID: "baserow-row-\($0.offset)", revision: 1, narration: $0.element)
        }
        review.prepareAudio = { _, _, _, _ in GuidedPreparedAudio(versionID: firstAudio, duration: 1) }
        var manualCalls = 0
        review.onAudioApproved = { _ in preconditionFailure("M started agent practice") }
        review.recordManualAudio = { approval in
            manualCalls += 1
            precondition(approval.audio.versionID == firstAudio)
            if manualCalls == 1 { throw NSError(domain: "PauseCheck", code: 1) }
        }
        try await review.beginChapter(chapter)
        review.improve()
        var revised = chapter[0]; revised.narration = "Revised first scene."; revised.revision = 2
        try await send("submit", draft: revised, eventID: review.decision!.id)
        review.approve()
        try await waitFor { review.phase == "audioReady" && !review.audioBusy }
        review.recordMyself(); review.recordMyself()
        try await waitFor { review.phase == "manualRetry" }
        precondition(manualCalls == 1 && review.draft == revised)
        review.recordMyself()
        try await waitFor { review.phase == "awaitingDecision" && review.draft == chapter[1] }
        review.approve()
        try await waitFor { review.phase == "audioReady" && !review.audioBusy }
        review.recordMyself()
        try await waitFor { !review.active }
        precondition(manualCalls == 3 && review.message == "Recording completed for this chapter.")
        // Backward-compatible decoding when earlier snapshots have no audio fields.
        var old = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("status.json"))) as! [String: Any]
        for key in ["audioReview", "audioDecision", "audioAcknowledged", "audioBusy"] { old.removeValue(forKey: key) }
        try JSONSerialization.data(withJSONObject: old).write(to: root.appendingPathComponent("status.json"))
        let legacy = GuidedNarrationReview(directory: root)
        precondition(!legacy.active)
        print("PASS: automatic wording-to-audio handoff, frozen wording/voice, A/G stage routing, busy press suppression, regeneration, exact audio approval/events, restart recovery, failure/retry, canceled generation and legacy snapshots; no real speech, TTS or recording")
    }
}
