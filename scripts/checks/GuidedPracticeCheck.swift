import CryptoKit
import Foundation

@MainActor private final class PracticePlayer: ApprovedAudioPlaying {
    var duration: Double = 4.6
    var currentTime: Double = 0
    var completion: ((Bool) -> Void)?
    var played = false
    var stopped = false
    var onPlay: () -> Void = {}
    func play() -> Bool { played = true; onPlay(); return true }
    func stop() { stopped = true }
}

@main struct GuidedPracticeCheck {
    @MainActor static func main() async throws {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--bridge" {
            let root = URL(fileURLWithPath: CommandLine.arguments[2])
            let bridge = GuidedPracticeSession(directory: root)
            let bytes = Data("fixture-only-approved-audio".utf8)
            let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            let draft = GuidedNarrationDraft(sessionID: UUID(), sceneID: "fixture-bridge", revision: 1, narration: "Click equals.")
            let audio = GuidedAudioReview(voice: GuidedAudioVoice(id: "fixture", name: "Fixture"), attempt: 1, versionID: UUID(), duration: 4.6)
            let decision = GuidedAudioDecision(id: UUID(), draft: draft, audio: audio, createdAt: Date())
            bridge.loadAssets = { event in
                GuidedPracticeAssets(context: GuidedPracticeContext(draft: event.draft, audioApprovalID: event.id,
                    audioVersionID: event.audio.versionID!, audioSHA256: hash, duration: 4.6, audioPath: "/fixture/audio.wav",
                    transcriptionPath: "/fixture/transcription.json", words: [GuidedPracticeWord(word: "Click", start: 0, end: 0.2)]), audio: bytes)
            }
            bridge.canPractice = { nil }; bridge.prompt = { _ in true }
            bridge.makePlayer = { _ in
                let player = PracticePlayer()
                player.onPlay = { [weak player] in Task { @MainActor in try? await Task.sleep(for: .milliseconds(20)); player?.completion?(true) } }
                return player
            }
            bridge.recordAudio = { _ in GuidedPracticeRecordingResult(sessionID: UUID(), duration: 4.6, message: "Fixture recording completed.") }
            bridge.start(); bridge.begin(decision)
            for _ in 0..<1000 {
                if bridge.phase == "practiceReady" { bridge.approve() }
                if FileManager.default.fileExists(atPath: root.appendingPathComponent("quit").path) { bridge.stop(); return }
                try await Task.sleep(for: .milliseconds(20))
            }
            bridge.stop(); throw NSError(domain: "PracticeBridge", code: 1)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("guided-practice-check-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let practice = GuidedPracticeSession(directory: root)
        let bytes = Data("fixture-frozen-approved-audio".utf8)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let draft = GuidedNarrationDraft(sessionID: UUID(), sceneID: "fixture-scene", revision: 1, narration: "Let's add twelve and eight.")
        let audio = GuidedAudioReview(voice: GuidedAudioVoice(id: "voice-a", name: "Voice A"), attempt: 2, versionID: UUID(), duration: 4.6)
        let approval = GuidedAudioDecision(id: UUID(), draft: draft, audio: audio, createdAt: Date())
        func assets(_ approval: GuidedAudioDecision) -> GuidedPracticeAssets {
            let context = GuidedPracticeContext(draft: approval.draft, audioApprovalID: approval.id,
                audioVersionID: approval.audio.versionID!, audioSHA256: hash, duration: 4.6,
                audioPath: "/fixture/audio.wav", transcriptionPath: "/fixture/transcription.json",
                words: [GuidedPracticeWord(word: "Let's", start: 0.1, end: 0.3), GuidedPracticeWord(word: "add", start: 0.4, end: 0.7)])
            return GuidedPracticeAssets(context: context, audio: bytes)
        }
        var loads = 0, recordCalls = 0
        var recorderContinuation: CheckedContinuation<GuidedPracticeRecordingResult, Never>?
        var player = PracticePlayer()
        practice.loadAssets = { event in loads += 1; return assets(event) }
        practice.canPractice = { nil }
        practice.prompt = { _ in true }
        practice.makePlayer = { data in precondition(data == bytes); player = PracticePlayer(); return player }
        practice.recordAudio = { material in
            precondition(material.context.audioVersionID == approval.audio.versionID && material.audio == bytes)
            recordCalls += 1
            return await withCheckedContinuation { recorderContinuation = $0 }
        }
        func waitFor(_ condition: @MainActor () -> Bool) async throws {
            for _ in 0..<200 { if condition() { return }; try await Task.sleep(for: .milliseconds(5)) }
            preconditionFailure("Timed out: \(practice.phase)")
        }
        func send(_ kind: String, run: UUID? = nil, plan: GuidedPracticePlan? = nil,
                  gate: GuidedPracticeGate? = nil, results: [GuidedPracticeActionResult]? = nil,
                  accepted: Bool = true) async throws -> GuidedPracticeCommand {
            let command = GuidedPracticeCommand(id: UUID(), sessionID: practice.approval!.draft.sessionID,
                runID: run ?? practice.runID!, kind: kind, plan: plan, gate: gate, results: results)
            let path = root.appendingPathComponent("commands/\(command.id.uuidString).json")
            try GuidedNarrationReview.encoder().encode(command).write(to: path, options: .atomic)
            practice.start() // The first command is already on disk when the watcher starts.
            let receipt = root.appendingPathComponent("receipts").appendingPathComponent(path.lastPathComponent)
            try await waitFor { FileManager.default.fileExists(atPath: receipt.path) }
            let result = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("receipts/\(path.lastPathComponent)"))) as! [String: Any]
            precondition(result["accepted"] as? Bool == accepted, result.description)
            return command
        }
        precondition(!practice.approve() && !practice.redo())
        practice.begin(approval)
        try await waitFor { practice.phase == "practiceRequested" }
        precondition(loads == 1 && practice.pendingEvent?.kind == "practiceRequested")
        let firstRun = practice.runID!
        practice.approve(); precondition(recordCalls == 0)
        let checkpoint = UUID()
        var plan = GuidedPracticePlan(id: UUID(), audioVersionID: audio.versionID!, audioSHA256: hash,
            checkpointID: checkpoint, actions: [GuidedPracticeAction(id: "click", description: "Click one", wordIndex: 1)])
        var bad = plan; bad.audioSHA256 = "wrong"
        _ = try await send("plan", plan: bad, accepted: false)
        bad = plan; bad.actions[0].wordIndex = 99
        _ = try await send("plan", plan: bad, accepted: false)
        _ = try await send("plan", plan: plan)
        let evidence = root.appendingPathComponent("checkpoint-evidence.json")
        try Data(#"{"fixture":true,"matched":true}"#.utf8).write(to: evidence)
        var gate = GuidedPracticeGate(checkpointID: checkpoint, verifiedAt: Date(), matched: true, evidencePath: evidence.path)
        var staleGate = gate; staleGate.verifiedAt = Date().addingTimeInterval(-60)
        _ = try await send("start", gate: staleGate, accepted: false)
        precondition(!player.played)
        _ = try await send("record", gate: gate, accepted: false)
        _ = try await send("start", gate: gate)
        precondition(practice.phase == "practicing" && player.played && recordCalls == 0)
        player.currentTime = 0.5; await practice.processInbox()
        precondition(abs(practice.elapsed - 0.5) < 0.001 && practice.currentWordIndex == 1)
        let results = [GuidedPracticeActionResult(actionID: "click", startedAtSeconds: 0.4, completedAtSeconds: 0.6, succeeded: true)]
        _ = try await send("finish", results: results)
        practice.approve(); precondition(recordCalls == 0 && practice.phase == "practicing")
        player.completion?(true)
        precondition(practice.phase == "practiceReady" && practice.promptBusy)
        precondition(practice.audioFinished && practice.actionsFinished)
        // G can interrupt the ready announcement and repeat without waiting for it.
        // A prep announcement failing must never swallow an improvement request.
        practice.prompt = { text in !text.hasPrefix("Preparing improved practice") }
        practice.redo()
        try await waitFor { practice.phase == "practiceRequested" }
        precondition(practice.runID != firstRun && loads == 1 && practice.attempt == 2)
        _ = try await send("start", run: firstRun, gate: gate, accepted: false)
        bad = plan; bad.checkpointID = UUID()
        _ = try await send("plan", plan: bad, accepted: false)
        plan.id = UUID(); _ = try await send("plan", plan: plan)
        gate.verifiedAt = Date(); _ = try await send("start", gate: gate)
        player.completion?(true)
        precondition(practice.phase == "waitingForActions")
        practice.approve(); precondition(recordCalls == 0)
        _ = try await send("finish", results: results)
        try await waitFor { practice.phase == "practiceReady" && !practice.promptBusy }
        practice.approve(); practice.approve()
        try await waitFor { practice.phase == "recordRequested" && !practice.promptBusy }
        precondition(practice.pendingEvent?.kind == "recordRequested" && recordCalls == 0)
        _ = try await send("record", gate: staleGate, accepted: false)
        gate.verifiedAt = Date(); let recordCommand = try await send("record", gate: gate)
        try await waitFor { recorderContinuation != nil }
        precondition(recordCalls == 1)
        await practice.processInbox() // The same command receipt cannot start another take.
        practice.approve(); practice.redo(); precondition(recordCalls == 1)
        _ = try await send("record", gate: gate, accepted: false)
        _ = try await send("recordFinish", results: results, accepted: false)
        var recordResults = results; recordResults[0].captureState = "recording"
        _ = try await send("recordFinish", results: recordResults)
        precondition(practice.phase == "recording")
        let takeID = UUID()
        recorderContinuation?.resume(returning: GuidedPracticeRecordingResult(sessionID: takeID, duration: 4.6, message: "Pause command sent."))
        try await waitFor { practice.phase == "completed" && !practice.promptBusy }
        precondition(practice.recordingResult?.sessionID == takeID && practice.pendingEvent?.kind == "recordingCompleted")
        let restored = GuidedPracticeSession(directory: root)
        precondition(restored.active && restored.phase == "suspended", "Restart must never restore permission to autoplay or record")
        precondition(recordCommand.runID == practice.runID)
        practice.end(); precondition(!practice.approve() && !practice.redo())

        // Exercise the actual ten-action router, including an edit during playback.
        let review = GuidedNarrationReview(directory: root.appendingPathComponent("review"))
        review.canSpeak = { nil }
        review.speak = { _, token in review.speechFinished(token) }
        review.selectedAudioVoice = { audio.voice }
        var preparedTexts: [String] = []
        review.prepareAudio = { text, voiceID, _, isCurrent in
            precondition(isCurrent() && voiceID == audio.voice.id)
            preparedTexts.append(text)
            return GuidedPreparedAudio(versionID: UUID(), duration: 4.6)
        }
        var previewWaiter: CheckedContinuation<Void, Never>?
        review.previewAudio = { _, _ in await withCheckedContinuation { previewWaiter = $0 } }
        var stoppedVersions: [UUID] = []
        review.stopAudioPreview = { if let id = $0 { stoppedVersions.append(id) } }
        review.approveAudioVersion = { _, _, _ in }
        review.onAudioApproved = { practice.begin($0) }
        review.onEnd = { practice.end() }
        let last = GuidedNarrationDraft(sessionID: UUID(), sceneID: "next-row", revision: 1, narration: "Next scene.")
        try await review.beginChapter([draft, last])
        func press(_ action: GuidedAction) { action.perform(review, practice) }
        press(.replayNarration)
        await Task.yield()
        press(.approveWording)
        try await waitFor { previewWaiter != nil }
        let discarded = review.audioReview!.versionID!
        press(.improveWording)
        precondition(review.phase == "improving" && stoppedVersions.contains(discarded))
        precondition(review.audioReview?.versionID == nil && review.audioDecision == nil)
        let restoredEdit = GuidedNarrationReview(directory: review.directory)
        precondition(restoredEdit.decision?.id == review.decision?.id && restoredEdit.phase == "improving")
        previewWaiter?.resume(); previewWaiter = nil
        var revision = draft; revision.revision += 1; revision.narration = "Revised wording."
        let command = GuidedNarrationCommand(id: UUID(), sessionID: draft.sessionID, kind: "submit", draft: revision, eventID: review.decision!.id)
        try GuidedNarrationReview.encoder().encode(command).write(to: review.directory.appendingPathComponent("commands/\(command.id).json"), options: .atomic)
        await review.processInbox()
        review.selectedAudioVoice = { nil } // The revision keeps the initially selected voice.
        review.previewAudio = { _, _ in }
        press(.approveWording)
        try await waitFor { review.phase == "audioReady" && !review.audioBusy }
        let revisedVersion = review.audioReview!.versionID!
        press(.replayVoice)
        try await waitFor { !review.audioBusy }
        precondition(review.audioReview?.versionID == revisedVersion && preparedTexts == [draft.narration, revision.narration])
        press(.regenerateVoice)
        try await waitFor { review.phase == "audioReady" && !review.audioBusy }
        let finalVersion = review.audioReview!.versionID!
        precondition(finalVersion != revisedVersion)
        press(.startPractice)
        try await waitFor { practice.phase == "practiceRequested" }
        var handoffPlan = plan; handoffPlan.audioVersionID = finalVersion
        _ = try await send("plan", plan: handoffPlan)
        gate.verifiedAt = Date()
        _ = try await send("start", gate: gate)
        _ = try await send("finish", results: results)
        player.completion?(true)
        press(.replayPractice)
        precondition(practice.phase == "practiceRequested" && practice.plan?.id == handoffPlan.id)
        precondition(practice.pendingEvent?.kind == "practiceReplayRequested")
        _ = try await send("start", gate: gate)
        _ = try await send("finish", results: results)
        player.completion?(true)
        var manualCalls = 0
        review.recordManualAudio = { event in
            precondition(event.audio.versionID == finalVersion && event.draft == revision)
            manualCalls += 1
        }
        press(.manual); press(.manual); press(.agentRecord)
        precondition(practice.phase == "manualRestoreRequested" && manualCalls == 0)
        _ = try await send("manualReady", gate: staleGate, accepted: false)
        _ = try await send("manualReady", gate: gate)
        try await waitFor { practice.phase == "manualReady" && !practice.promptBusy }
        press(.manual); press(.manual)
        try await waitFor { review.draft == last }
        precondition(manualCalls == 1 && recordCalls == 1 && !practice.active)
        review.end()
        print("PASS: voice-preview wording revision, same-voice replay and regeneration, unchanged rehearsal replay, restored two-press manual handoff and single scene advance")

        // A late material loader cannot replace a newer session's frozen audio.
        var pendingAssets: CheckedContinuation<GuidedPracticeAssets, Never>?
        var oldApproval = approval; oldApproval.id = UUID()
        var newApproval = approval; newApproval.id = UUID(); newApproval.audio.versionID = UUID()
        let old = oldApproval, fresh = newApproval
        practice.loadAssets = { event in
            if event.id == old.id { return await withCheckedContinuation { pendingAssets = $0 } }
            return assets(event)
        }
        practice.begin(old); try await waitFor { pendingAssets != nil }
        practice.end(); practice.begin(fresh)
        try await waitFor { practice.phase == "practiceRequested" }
        pendingAssets?.resume(returning: assets(old))
        try await Task.sleep(for: .milliseconds(30))
        precondition(practice.approval?.id == fresh.id && practice.pendingEvent?.audioVersionID == fresh.audio.versionID)
        practice.end()
        print("PASS: approved WAV/word context, real-player clock, action/word anchors, no practice recording, A/G gates, same-audio redo, baseline restoration, stale/duplicate commands, recording action evidence, restart and late-loader cancellation; mocks only")
    }
}
