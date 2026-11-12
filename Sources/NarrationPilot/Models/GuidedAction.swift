import KeyboardShortcuts

enum GuidedAction: String, CaseIterable, Identifiable {
    case replayNarration = "Replay narration"
    case improveWording = "Improve wording"
    case approveWording = "Approve wording"
    case replayVoice = "Replay generated voice"
    case regenerateVoice = "Regenerate voice"
    case startPractice = "Start agent practice"
    case replayPractice = "Replay practice"
    case improvePractice = "Improve practice"
    case agentRecord = "Record with agent"
    case manual = "Record myself"

    var id: Self { self }

    var shortcut: KeyboardShortcuts.Name {
        switch self {
        case .replayNarration: .guidedReplayNarration
        case .improveWording: .guidedImproveWording
        case .approveWording: .approveClonedClipboardAudio
        case .replayVoice: .guidedReplayVoice
        case .regenerateVoice: .regenerateClonedClipboardAudio
        case .startPractice: .guidedStartPractice
        case .replayPractice: .guidedReplayPractice
        case .improvePractice: .guidedImprovePractice
        case .agentRecord: .guidedAgentRecord
        case .manual: .recordGuidedManually
        }
    }

    @MainActor func available(_ review: GuidedNarrationReview, _ practice: GuidedPracticeSession) -> Bool {
        guard review.active, let draft = review.draft, review.unsavedEditorSceneID != draft.sceneID,
              review.editorResetRequestID == nil else { return false }
        if practice.active {
            guard practice.approval?.id == review.audioDecision?.id else { return false }
            switch self {
            case .agentRecord, .replayPractice: return practice.phase == "practiceReady"
            case .improvePractice: return ["practiceReady", "blocked", "suspended"].contains(practice.phase)
            case .manual: return practice.phase == "practiceReady" || (practice.phase == "manualReady" && !practice.promptBusy)
            default: return false
            }
        }
        switch self {
        case .replayNarration: return review.decision == nil && ["reading", "awaitingDecision", "suspended", "blocked"].contains(review.phase)
        case .approveWording: return review.phase == "sentenceReady" && !review.audioBusy || review.decision == nil && ["reading", "awaitingDecision"].contains(review.phase)
        case .improveWording: return review.canImproveWording
        case .replayVoice: return review.decision?.kind == "approveNarration" && review.audioReview?.versionID != nil && review.audioDecision == nil
        case .regenerateVoice: return review.decision?.kind == "approveNarration" && review.audioDecision == nil && !review.audioBusy
        case .startPractice: return review.phase == "audioReady" && !review.audioBusy || review.phase == "audioApproved" && review.audioDecision != nil
        case .manual: return ["audioReady", "manualRetry"].contains(review.phase) && !review.audioBusy
        default: return false
        }
    }

    @MainActor func perform(_ review: GuidedNarrationReview, _ practice: GuidedPracticeSession, instruction: String? = nil) {
        guard available(review, practice) else { return }
        switch self {
        case .replayNarration: Task { await review.replay() }
        case .improveWording: review.improveWording(instruction: instruction)
        case .approveWording: review.approveWording()
        case .replayVoice: review.replayAudio()
        case .regenerateVoice: review.generateAudio(forceNewVersion: true)
        case .startPractice:
            if let approval = review.audioDecision { practice.begin(approval) }
            else { review.startAgentPractice() }
        case .replayPractice: practice.replayPractice()
        case .improvePractice: practice.redo(instruction: instruction)
        case .agentRecord: practice.approve()
        case .manual:
            if practice.phase == "practiceReady" { practice.requestManualRestore() }
            else if practice.phase == "manualReady", let approval = practice.approval {
                practice.end()
                review.startRestoredManualTake(approval)
            } else { review.recordMyself() }
        }
    }
}
