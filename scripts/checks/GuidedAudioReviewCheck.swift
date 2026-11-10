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
        func send(_ kind: String, draft: GuidedNarrationDraft, eventID: UUID? = nil, next: GuidedNarrationDraft? = nil, accepted: Bool = true) async throws {
            let c = GuidedNarrationCommand(id: UUID(), sessionID: draft.sessionID, kind: kind, draft: kind == "submit" ? draft : nil, eventID: eventID, nextCandidate: next)
            try GuidedNarrationReview.encoder().encode(c).write(to: root.appendingPathComponent("commands/\(c.id.uuidString).json"), options: .atomic)
            review.start() // The first command is already on disk when the watcher starts.
            let receipt = root.appendingPathComponent("receipts").appendingPathComponent(c.id.uuidString + ".json")
            try await waitFor { FileManager.default.fileExists(atPath: receipt.path) }
            let r = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("receipts/\(c.id.uuidString).json"))) as! [String: Any]
            precondition(r["accepted"] as? Bool == accepted, r.description)
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

        // Model the missing speech callback after the voice file has been saved.
        var missingCue: UUID?
        var retryDraft = draft
        retryDraft.sessionID = UUID()
        review.speak = { text, token in
            if text == "Review audio." { missingCue = token }
            else { review.speechFinished(token) }
        }
        review.previewAudio = { audio, _ in previews.append(audio.versionID) }
        try await send("submit", draft: retryDraft)
        review.approveWording()
        try await waitFor { missingCue != nil }
        let saved = review.audioReview!.versionID!
        let firstCue = missingCue!
        precondition(review.audioBusy && review.phase == "audioPreparing")
        let requestsBeforeReplay = prepared.count
        review.replayAudio()
        try await waitFor { review.phase == "audioReady" && !review.audioBusy }
        review.speechFinished(firstCue)
        precondition(previews.last == saved && prepared.count == requestsBeforeReplay)

        missingCue = nil
        review.generateAudio(forceNewVersion: true)
        try await waitFor { missingCue != nil }
        let supersededCue = missingCue!
        missingCue = nil
        review.generateAudio(forceNewVersion: true)
        try await waitFor { missingCue != nil }
        review.speechFinished(supersededCue)
        precondition(review.audioBusy)
        for _ in 0..<100 {
            if !review.audioBusy { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        precondition(review.phase == "audioReady" && !review.audioBusy && review.audioReview?.attempt == 3)
        review.speak = { _, token in review.speechFinished(token) }

        // A backend which returns after cancellation must not replace the newer take.
        let retryVersion = UUID(), staleVersion = UUID()
        var lateRequest: CheckedContinuation<GuidedPreparedAudio, Never>?
        review.prepareAudio = { _, _, _, _ in
            if lateRequest == nil { return await withCheckedContinuation { lateRequest = $0 } }
            return GuidedPreparedAudio(versionID: retryVersion, duration: 2)
        }
        review.generateAudio(forceNewVersion: true)
        try await waitFor { lateRequest != nil }
        review.generateAudio(forceNewVersion: true)
        try await waitFor { review.phase == "audioReady" && !review.audioBusy }
        lateRequest?.resume(returning: GuidedPreparedAudio(versionID: staleVersion, duration: 2))
        try await Task.sleep(for: .milliseconds(20))
        precondition(review.audioReview?.versionID == retryVersion && !previews.contains(staleVersion))
        review.end()
        print("PASS: direct replay during a stuck cue, bounded automatic preview and regeneration superseding a late response")

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
        var selectedScenes: [String] = []
        review.onChapterSceneSelected = { selectedScenes.append($0) }
        try await review.beginChapter(chapter)
        review.improve()
        var revised = chapter[0]; revised.narration = "Revised first scene."; revised.revision = 2
        var candidate = chapter[1]; candidate.narration = "The app is open."
        try await send("submit", draft: revised, eventID: review.decision!.id, next: chapter[0], accepted: false)
        try await send("submit", draft: revised, eventID: review.decision!.id, next: candidate)
        review.approve()
        try await waitFor { review.phase == "audioReady" && !review.audioBusy }
        review.recordMyself(); review.recordMyself()
        try await waitFor { review.phase == "manualRetry" }
        precondition(manualCalls == 1 && review.draft == revised)
        review.recordMyself()
        try await waitFor { review.phase == "awaitingDecision" && review.draft == candidate }
        review.approve()
        try await waitFor { review.phase == "audioReady" && !review.audioBusy }
        review.recordMyself()
        try await waitFor { !review.active }
        precondition(manualCalls == 3 && review.message == "Recording completed for this chapter.")
        precondition(selectedScenes == chapter.map(\.sceneID), "Manual takes should follow each selected row exactly once")
        selectedScenes = []
        // Pause and successful action completion advance speech before the runner saves its image.
        var freshChapter = chapter.map { GuidedNarrationDraft(sessionID: UUID(), sceneID: $0.sceneID, revision: 1, narration: $0.narration) }
        freshChapter.append(GuidedNarrationDraft(sessionID: UUID(), sceneID: "final", revision: 1, narration: "Ready for the first task."))
        var chapterAnnouncements = 0
        var promptStart: ContinuousClock.Instant?
        review.speak = { text, token in
            if text == "Recording completed for this chapter." { chapterAnnouncements += 1 }
            promptStart = .now
            review.heardFirstWord(token)
            review.speechFinished(token)
        }
        review.onAudioApproved = { _ in }
        try await review.beginChapter(freshChapter)
        review.approve()
        try await waitFor { review.phase == "audioReady" && !review.audioBusy }
        review.approve()
        let firstApproval = review.audioDecision!
        let pause = ContinuousClock.now
        review.chapterPauseConfirmed()
        await review.guidedTakeFinished(firstApproval)
        precondition(promptStart! >= pause && pause.duration(to: promptStart!) < .milliseconds(500))
        precondition(review.draft == freshChapter[1] && review.pendingEndingSessionID == freshChapter[0].sessionID)
        await review.guidedTakeFinished(firstApproval)
        review.approve()
        try await waitFor { review.phase == "audioReady" && !review.audioBusy }
        review.approve()
        precondition(review.audioDecision == nil, "Practice cannot move the screen before checkpoint acknowledgment")
        try await send("chapterTakeCompleted", draft: freshChapter[0])
        let middleApproval = review.audioDecision!
        let secondPause = ContinuousClock.now
        review.chapterPauseConfirmed()
        await review.guidedTakeFinished(middleApproval)
        precondition(review.draft == freshChapter[2] && chapterAnnouncements == 0)
        precondition(promptStart! >= secondPause && secondPause.duration(to: promptStart!) < .milliseconds(500))
        try await send("chapterTakeCompleted", draft: freshChapter[1])
        review.approve()
        try await waitFor { review.phase == "audioReady" && !review.audioBusy }
        review.approve()
        let lastApproval = review.audioDecision!
        review.chapterPauseConfirmed()
        await review.guidedTakeFinished(lastApproval)
        await review.guidedTakeFinished(lastApproval)
        precondition(!review.active && chapterAnnouncements == 1)
        precondition(selectedScenes == freshChapter.map(\.sceneID), "Guided takes should follow each selected row exactly once")
        try await send("chapterTakeCompleted", draft: freshChapter[2])
        precondition(chapterAnnouncements == 1 && review.pendingEndingSessionID == nil)
        print("PASS: next prompt before ending screenshot; pause-to-prompt request under 500 ms; chapter completion spoken once")
        let jump = freshChapter.map { GuidedNarrationDraft(sessionID: UUID(), sceneID: $0.sceneID, revision: 1, narration: $0.narration) }
        try await review.beginChapter(jump)
        review.approve()
        try await waitFor { review.phase == "audioReady" && !review.audioBusy }
        review.approve()
        let recording = review.audioDecision!
        review.practiceSummary = { ["phase": "recording"] }
        try await review.selectChapterScenes([jump[2]])
        precondition(review.draft == jump[0] && review.remainingChapterScenes == [jump[2]])
        await review.guidedTakeFinished(recording)
        precondition(review.draft == jump[2])
        review.practiceSummary = { nil }
        let revisited = GuidedNarrationDraft(sessionID: UUID(), sceneID: jump[0].sceneID, revision: 1, narration: jump[0].narration)
        try await review.selectChapterScenes([revisited])
        precondition(review.draft == revisited && review.decision == nil && review.audioReview == nil)
        precondition(review.pendingEndingSessionID == jump[0].sessionID)
        try await send("chapterTakeCompleted", draft: jump[0])
        review.end()
        print("PASS: deferred row selection during recording and backward jump with pending checkpoint")
        // A wording edit during capture belongs to a new take on the same row.
        let editQueue = chapter.map { GuidedNarrationDraft(sessionID: UUID(), sceneID: $0.sceneID, revision: 1, narration: $0.narration) }
        try await review.beginChapter(editQueue)
        review.approve()
        try await waitFor { review.phase == "audioReady" && !review.audioBusy }
        review.approve()
        let originalTake = review.audioDecision!
        review.practiceSummary = { ["phase": "recording"] }
        try await review.replaceCurrentSceneWording("First edit.")
        try await review.replaceCurrentSceneWording("Final edit.")
        precondition(review.draft == originalTake.draft)
        precondition(review.remainingChapterScenes?.map(\.sceneID) == editQueue.map(\.sceneID))
        await review.guidedTakeFinished(originalTake)
        precondition(review.draft?.sceneID == editQueue[0].sceneID && review.draft?.narration == "Final edit.")
        precondition(review.draft?.sessionID != originalTake.draft.sessionID && review.audioReview == nil && review.decision == nil)
        precondition(review.pendingEndingSessionID == originalTake.draft.sessionID)
        review.end()
        print("PASS: same-row wording edits during capture restart once with the latest wording after the take")
        // Backward-compatible decoding when earlier snapshots have no audio fields.
        var old = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("status.json"))) as! [String: Any]
        for key in ["audioReview", "audioDecision", "audioAcknowledged", "audioBusy"] { old.removeValue(forKey: key) }
        try JSONSerialization.data(withJSONObject: old).write(to: root.appendingPathComponent("status.json"))
        let legacy = GuidedNarrationReview(directory: root)
        precondition(!legacy.active)
        print("PASS: automatic wording-to-audio handoff, frozen wording/voice, A/G stage routing, busy press suppression, regeneration, exact audio approval/events, restart recovery, failure/retry, canceled generation and legacy snapshots; no real speech, TTS or recording")
    }
}
