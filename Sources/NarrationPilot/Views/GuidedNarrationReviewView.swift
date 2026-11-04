import KeyboardShortcuts
import SwiftUI

struct GuidedNarrationReviewView: View {
    @ObservedObject var review: GuidedNarrationReview
    var body: some View {
        GroupBox("Guided Narration Review") {
            VStack(alignment: .leading, spacing: 8) {
                Text(review.active ? "Review narration · \(review.phase)" : "Guided review inactive").font(.subheadline.bold())
                Text(review.message).font(.caption).textSelection(.enabled)
                if let draft = review.draft, review.active {
                    Text("\(draft.sceneID) · revision \(draft.revision)").font(.caption).foregroundStyle(.secondary)
                    Text(draft.narration).textSelection(.enabled)
                    HStack {
                        Button("Approve Wording") { review.approve() }
                        Button("Improve Wording") { review.improve() }
                    }.disabled(review.decision != nil || !["reading", "awaitingDecision"].contains(review.phase))
                    HStack {
                        Button("Replay Narration") { Task { await review.replay() } }.disabled(review.decision != nil || review.phase == "checking")
                        Button("End Guided Review") { review.end() }
                    }
                }
                KeyboardShortcuts.Recorder("Approve current review / audio", name: .approveClonedClipboardAudio)
                KeyboardShortcuts.Recorder("Improve wording / regenerate audio", name: .regenerateClonedClipboardAudio)
                Text("During guided narration review these shortcuts approve wording or request improvement. Outside review they retain audio approval and regeneration. Uses a separate macOS speech preview; never starts recording or cloned TTS.")
                    .font(.caption2).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
        }
    }
}
