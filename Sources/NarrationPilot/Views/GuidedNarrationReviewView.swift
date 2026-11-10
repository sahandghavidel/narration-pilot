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
                    GuidedReviewActions(review: review, practice: practice)
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

private struct GuidedReviewActions: View {
    @ObservedObject var review: GuidedNarrationReview
    @ObservedObject var practice: GuidedPracticeSession

    var showsImprovementOptions = false
    @State private var optionsFor: GuidedAction?
    @State private var custom = false
    @State private var instruction = ""
    @FocusState private var editingInstruction: Bool

    private var actions: [GuidedAction] { GuidedAction.allCases.filter { $0.available(review, practice) } }

    private func showOptions(_ action: GuidedAction?) {
        editingInstruction = false
        instruction = ""
        custom = false
        optionsFor = action
    }

    private func submit(_ text: String, for action: GuidedAction) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, action.available(review, practice) else { return }
        showOptions(nil)
        action.perform(review, practice, instruction: value)
    }

    private func presets(for action: GuidedAction) -> [String] {
        if action == .improveWording {
            return ["Make it shorter", "Add a little detail", "Make it sound like me", "Make it clearer for beginners"]
        }
        return ["Make the actions faster", "Make the actions slower", "Match the narration better", "Show the result longer"]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let audio = review.audioReview {
                Text("\(audio.voice.name) · attempt \(audio.attempt)").font(.caption)
                if let duration = audio.duration {
                    Text("Saved audio: \(duration, specifier: "%.2f") seconds").font(.caption).monospacedDigit()
                }
            }
            if review.audioBusy { ProgressView().controlSize(.small) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 175))], alignment: .leading) {
                ForEach(actions) { action in
                    HStack(spacing: 3) {
                        Button {
                            showOptions(nil)
                            action.perform(review, practice)
                        } label: {
                            HStack {
                                Text(action.rawValue)
                                if let shortcut = action.shortcut.shortcut {
                                    Text(String(describing: shortcut)).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if showsImprovementOptions && [.improveWording, .improvePractice].contains(action) {
                            Button {
                                showOptions(optionsFor == action ? nil : action)
                            } label: {
                                Image(systemName: optionsFor == action ? "chevron.up" : "chevron.down")
                            }
                            .accessibilityLabel("\(action.rawValue) options")
                            .help("Choose how to improve this \(action == .improveWording ? "narration" : "practice")")
                        }
                    }
                }
            }
            if let action = optionsFor, actions.contains(action) {
                if custom {
                    Text(action == .improveWording ? "What should change in the wording?" : "What should change in the practice?")
                        .font(.caption)
                    TextEditor(text: $instruction)
                        .frame(height: 60)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(.secondary.opacity(0.3)))
                        .focused($editingInstruction)
                        .accessibilityLabel("Custom improvement instruction")
                        .task {
                            await Task.yield()
                            editingInstruction = true
                        }
                    HStack {
                        Button("Send instruction") { submit(instruction, for: action) }
                            .disabled(instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Cancel") { showOptions(nil) }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], alignment: .leading) {
                        ForEach(presets(for: action), id: \.self) { preset in
                            Button(preset) { submit(preset, for: action) }
                        }
                        Button("Give my own instruction…") { custom = true }
                    }
                }
            }
            if showsImprovementOptions {
                if review.phase == "improving", let request = review.decision?.instruction {
                    Text("Requested: \(request)").font(.caption).textSelection(.enabled)
                } else if practice.active, practice.phase == "practiceRequested", let request = practice.pendingEvent?.instruction {
                    Text("Requested: \(request)").font(.caption).textSelection(.enabled)
                }
            }
        }
        .onChange(of: actions) {
            if let action = optionsFor, !actions.contains(action) { showOptions(nil) }
        }
    }
}

struct SceneManagerGuidedReview: View {
    @ObservedObject var review: GuidedNarrationReview
    @ObservedObject var practice: GuidedPracticeSession
    let scene: NarrationScene
    let wordingEdited: Bool
    let save: () -> Void

    private var heading: String {
        if !review.active { return "Guided Review" }
        if practice.active { return "Practice and recording" }
        if review.phase.hasPrefix("manual") { return "Manual recording" }
        return review.decision?.kind == "approveNarration" ? "Review voice" : "Review wording"
    }

    var body: some View {
        GroupBox(heading) {
            VStack(alignment: .leading, spacing: 6) {
                if wordingEdited {
                    Button(review.active && review.remainingChapterScenes != nil && review.draft?.sceneID == scene.id ? "Save & hear changes" : "Save wording") { save() }
                } else if !review.active {
                    if review.pendingEndingSessionID != nil {
                        Text("Saving the final scene’s ending screen…").font(.caption)
                    } else {
                        GuidedSceneSelection(popupSceneID: scene.id)
                    }
                } else if review.draft?.sceneID == scene.id, review.remainingChapterScenes != nil {
                    Text(practice.active ? practice.message : review.message).font(.caption)
                    if let draft = review.draft, draft.narration != scene.narration {
                        Text("Current guided wording").font(.caption.bold())
                        Text(draft.narration).textSelection(.enabled)
                    }
                    GuidedReviewActions(review: review, practice: practice, showsImprovementOptions: true)
                        .id(review.draft?.sessionID)
                        .id(review.draft?.revision)
                        .id(practice.runID)
                    Button("End Guided Review") { review.end() }.controlSize(.small)
                } else {
                    Text("Guided Review is on another scene.").font(.caption)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct GuidedSceneSelection: View {
    var popupSceneID: String? = nil
    @EnvironmentObject private var appModel: AppModel
    @State private var busy = false
    @State private var issue = ""

    var body: some View {
        VStack(alignment: .leading) {
            if let selection = appModel.guidedSceneSelection {
                if popupSceneID == nil { Text(selection.label).font(.subheadline.bold()) }
                Button(popupSceneID == nil ? "Start Chapter Review" : "Start review from this scene") {
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
            if popupSceneID == nil { Button("Open Scene Manager") { appModel.openCurrentSceneEditor() } }
            if !issue.isEmpty { Text(issue).font(.caption) }
        }
        .disabled(busy || appModel.isBaserowSyncing || (popupSceneID != nil && popupSceneID != appModel.currentNarrationScene?.id))
        .onChange(of: appModel.guidedSceneSelection) { issue = "" }
    }
}
