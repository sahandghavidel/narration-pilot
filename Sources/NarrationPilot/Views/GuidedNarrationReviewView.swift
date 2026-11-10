import KeyboardShortcuts
import SwiftUI

struct GuidedNarrationReviewView: View {
    @ObservedObject var review: GuidedNarrationReview
    @ObservedObject var practice: GuidedPracticeSession
    @EnvironmentObject private var appModel: AppModel
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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 175))], alignment: .leading) {
                        ForEach(GuidedAction.allCases.filter { $0.available(review, practice) }) { action in
                            Button {
                                action.perform(review, practice)
                            } label: {
                                HStack {
                                    Text(action.rawValue)
                                    if let shortcut = action.shortcut.shortcut {
                                        Text(String(describing: shortcut)).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    Button("End Guided Review") { review.end() }
                }
                DisclosureGroup("Guided shortcuts") {
                    ForEach(GuidedAction.allCases) { action in
                        KeyboardShortcuts.Recorder(action.rawValue, name: action.shortcut) { _ in
                            appModel.refreshGuidedShortcuts(force: true)
                        }
                    }
                    Button("Restore guided defaults") {
                        KeyboardShortcuts.reset(GuidedAction.allCases.map(\.shortcut))
                        appModel.refreshGuidedShortcuts(force: true)
                    }
                }
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
