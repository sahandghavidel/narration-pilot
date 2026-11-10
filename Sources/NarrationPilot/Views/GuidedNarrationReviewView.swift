import KeyboardShortcuts
import SwiftUI

struct GuidedNarrationReviewView: View {
    @ObservedObject var review: GuidedNarrationReview
    private var reviewingAudio: Bool { review.decision?.kind == "approveNarration" }
    var body: some View {
        GroupBox("Guided Narration & Audio Review") {
            VStack(alignment: .leading, spacing: 8) {
                if !review.active {
                    if review.pendingEndingSessionID != nil {
                        Text("Saving the final scene’s ending screen…")
                        Button("End Without Ending Checkpoint") { review.end() }
                    } else {
                        GuidedSceneSelection()
                    }
                }
                Text(review.active ? "Review \(reviewingAudio ? "audio" : "narration") · \(review.phase)" : "Guided review inactive").font(.subheadline.bold())
                Text(review.message).font(.caption).textSelection(.enabled)
                if let draft = review.draft, review.active {
                    Text("\(draft.sceneID) · revision \(draft.revision)").font(.caption).foregroundStyle(.secondary)
                    Text(draft.narration).textSelection(.enabled)
                    if let audio = review.audioReview {
                        Text("\(audio.voice.name) · attempt \(audio.attempt)").font(.caption)
                        if let duration = audio.duration {
                            Text("Saved audio: \(duration, specifier: "%.2f") seconds").font(.caption).monospacedDigit()
                        }
                    }
                    if review.audioBusy { ProgressView().controlSize(.small) }
                    HStack {
                        Button(reviewingAudio ? "Approve Audio" : "Approve Wording") { review.approve() }
                            .disabled(review.audioBusy || (reviewingAudio ? review.phase != "audioReady" : !["reading", "awaitingDecision"].contains(review.phase)))
                        Button(reviewingAudio ? "Regenerate Audio" : "Improve Wording") { review.improve() }
                            .disabled(review.audioBusy || (reviewingAudio ? !["approved", "audioReady", "audioFailed", "audioSuspended"].contains(review.phase) : !["reading", "awaitingDecision"].contains(review.phase)))
                    }
                    if ["audioReady", "manualRetry"].contains(review.phase) {
                        Button("Record Myself") { review.recordMyself() }
                    }
                    HStack {
                        if reviewingAudio {
                            Button("Replay Saved Audio") { review.replayAudio() }
                                .disabled(review.audioBusy || review.audioReview?.versionID == nil || review.audioDecision != nil)
                            if review.audioReview == nil {
                                Button("Generate Audio") { review.generateAudio() }.disabled(review.audioBusy || review.audioDecision != nil)
                            }
                        } else {
                            Button("Replay Narration") { Task { await review.replay() } }.disabled(review.decision != nil || review.phase == "checking")
                        }
                        Button("End Guided Review") { review.end() }
                    }
                }
                HStack {
                    KeyboardShortcuts.Recorder("Approve wording / audio / practice", name: .approveClonedClipboardAudio)
                    Button("Use ⇧⌘A") { KeyboardShortcuts.reset(.approveClonedClipboardAudio) }
                        .help("Restore Command-Shift-A for approval")
                }
                KeyboardShortcuts.Recorder("Improve / regenerate / improve practice", name: .regenerateClonedClipboardAudio)
                KeyboardShortcuts.Recorder("Record myself", name: .recordGuidedManually)
                KeyboardShortcuts.Recorder("Record myself (alternate)", name: .recordGuidedManuallyAlternate)
                Text("Approve the wording to hear the voice. Then choose Record Myself to perform the actions, or approve the voice for guided practice. After the take, the next Baserow scene is read aloud.")
                    .font(.caption2).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
        }
    }
}

private struct GuidedSceneSelection: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var busy = false
    @State private var issue = ""

    var body: some View {
        VStack(alignment: .leading) {
            if let selection = appModel.guidedSceneSelection {
                Text(selection.label).font(.subheadline.bold())
                Button("Start Chapter Review") {
                    Task {
                        busy = true
                        issue = ""
                        defer { busy = false }
                        do { try await appModel.startBaserowReview(selection) }
                        catch { issue = error.localizedDescription }
                    }
                }
            } else {
                Text("Connect Baserow and select a scene in the Scene Manager.")
                    .font(.caption)
            }
            Button("Open Scene Manager") { appModel.openCurrentSceneEditor() }
            if !issue.isEmpty { Text(issue).font(.caption) }
        }
        .disabled(busy || appModel.isBaserowSyncing)
        .onChange(of: appModel.guidedSceneSelection) { issue = "" }
    }
}
