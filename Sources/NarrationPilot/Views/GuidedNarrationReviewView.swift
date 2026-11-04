import KeyboardShortcuts
import SwiftUI

struct GuidedNarrationReviewView: View {
    @ObservedObject var review: GuidedNarrationReview
    private var reviewingAudio: Bool { review.decision?.kind == "approveNarration" }
    var body: some View {
        GroupBox("Guided Narration & Audio Review") {
            VStack(alignment: .leading, spacing: 8) {
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
                KeyboardShortcuts.Recorder("Approve wording / audio / practice", name: .approveClonedClipboardAudio)
                KeyboardShortcuts.Recorder("Improve / regenerate / redo practice", name: .regenerateClonedClipboardAudio)
                Text("Approve wording to automatically prepare and preview cloned audio. During audio review, approve saves the exact candidate and redo regenerates the same wording and voice. Audio approval prepares guided practice. After a finished practice, approve requests recording once the agent restores the starting screen. Existing macOS speech controls are unchanged.")
                    .font(.caption2).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
        }
    }
}
