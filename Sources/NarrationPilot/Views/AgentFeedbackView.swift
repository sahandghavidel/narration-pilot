import KeyboardShortcuts
import SwiftUI

struct AgentFeedbackView: View {
    @ObservedObject var feedback: AgentFeedbackPublisher

    var body: some View {
        DisclosureGroup("Agent Feedback") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Publish local scene and recording feedback", isOn: $feedback.enabled)
                Text(feedback.sceneSummary).font(.caption).textSelection(.enabled)
                Text("Latest take: \(feedback.latestTakeSummary)").font(.caption)
                if let error = feedback.latestError { Text(error).font(.caption).foregroundStyle(.orange) }
                Text(feedback.summary).font(.caption).textSelection(.enabled)
                Text("Shares loaded scene text, prompts, commands, speech progress, and observed FocuSee state locally. Duration is estimated; capture state does not verify saved footage.")
                    .font(.caption2).foregroundStyle(.secondary)
                if let error = feedback.writeError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                HStack {
                    Button("Copy Current Scene for Agent") { feedback.copySnapshot() }
                    Button("Open Feedback Folder") { feedback.openFolder() }
                }
                KeyboardShortcuts.Recorder("Copy Current Scene for Agent", name: .copyCurrentSceneForAgent)
                Text(AgentFeedbackPublisher.statusURL.path)
                    .font(.caption2).textSelection(.enabled)
                Text("Live status expires after 4 seconds without updates. Recent history is limited to 20 takes and 100 events; disabling removes the live file.")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(.top, 6)
        }
    }
}
