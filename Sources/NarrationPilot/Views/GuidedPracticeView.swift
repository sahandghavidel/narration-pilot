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
                        Button("Stop Guided Take") { practice.suspend(pauseRecording: true) }
                    }
                }.padding(4).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
