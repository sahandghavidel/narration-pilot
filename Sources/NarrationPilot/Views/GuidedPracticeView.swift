import SwiftUI

struct GuidedPracticeView: View {
    @ObservedObject var practice: GuidedPracticeSession
    @ObservedObject var review: GuidedNarrationReview
    var body: some View {
        if practice.active || (review.active && review.audioDecision != nil) {
            GroupBox("Guided Practice & Recording") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Practice · \(practice.phase)").font(.subheadline.bold())
                    Text(practice.message).font(.caption).textSelection(.enabled)
                    if practice.active {
                        Text("Attempt \(practice.attempt) · \(practice.elapsed, specifier: "%.1f") / \(practice.duration, specifier: "%.1f") seconds")
                            .font(.caption).monospacedDigit()
                        if practice.duration > 0 { ProgressView(value: min(practice.elapsed, practice.duration), total: practice.duration) }
                        if let plan = practice.plan { Text("\(plan.actions.count) planned actions · word/audio timing anchors").font(.caption) }
                        HStack {
                            Button("Approve Practice & Record") { practice.approve() }
                                .disabled(practice.phase != "practiceReady")
                            Button("Redo Practice") { practice.redo() }
                                .disabled(!["practiceReady", "practicing", "waitingForActions", "waitingForRecordActions", "recordRequested", "blocked", "suspended"].contains(practice.phase))
                        }
                        Button("Stop Guided Take") { practice.suspend(pauseRecording: true) }
                    } else if let approval = review.audioDecision {
                        Button("Prepare Practice (Redo shortcut)") { practice.begin(approval) }
                    }
                    Text("A approves a finished practice and asks the agent to restore the start before recording. G repeats practice with the same approved WAV. Practice plays audio while FocuSee is paused; saved word timings guide the agent's actions. An active agent session is required.")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding(4).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
