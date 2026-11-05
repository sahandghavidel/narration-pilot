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
                        GuidedChapterPicker()
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
                KeyboardShortcuts.Recorder("Approve wording / audio / practice", name: .approveClonedClipboardAudio)
                KeyboardShortcuts.Recorder("Improve / regenerate / redo practice", name: .regenerateClonedClipboardAudio)
                KeyboardShortcuts.Recorder("Record myself", name: .recordGuidedManually)
                KeyboardShortcuts.Recorder("Record myself (alternate)", name: .recordGuidedManuallyAlternate)
                Text("Approve the wording to hear the voice. Then choose Record Myself to perform the actions, or approve the voice for guided practice. After the take, the next Baserow scene is read aloud.")
                    .font(.caption2).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
        }
    }
}

private struct GuidedChapterPicker: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var scripts: [BaserowScriptRecord] = []
    @State private var rows: [BaserowSceneRecord] = []
    @State private var scriptID = 0
    @State private var part = ""
    @State private var rowID = 0
    @State private var busy = false
    @State private var issue = ""

    private var parts: [String] {
        Set(rows.filter { $0.scriptIDs.contains(scriptID) }.compactMap(\.part)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }
    private var scenes: [BaserowSceneRecord] { rows.filter { $0.scriptIDs.contains(scriptID) && $0.part == part } }

    var body: some View {
        VStack(alignment: .leading) {
            Button(scripts.isEmpty ? "Choose Baserow Chapter" : "Reload Baserow Chapters") {
                Task { await load() }
            }
            if !scripts.isEmpty {
                Picker("Script", selection: $scriptID) {
                    ForEach(scripts) { Text($0.title).tag($0.rowID) }
                }.onChange(of: scriptID) { selectFirstPart() }
                Picker("Chapter", selection: $part) {
                    ForEach(parts, id: \.self) { Text($0).tag($0) }
                }.onChange(of: part) { rowID = scenes.first?.rowID ?? 0 }
                Picker("Start at", selection: $rowID) {
                    ForEach(scenes, id: \.rowID) { Text("Scene \($0.originalSceneNumber)").tag($0.rowID) }
                }
                Button("Start Chapter Review") {
                    Task {
                        busy = true; issue = ""
                        defer { busy = false }
                        do { try await appModel.startBaserowReview(script: scriptID, part: part, startRow: rowID) }
                        catch { issue = error.localizedDescription }
                    }
                }.disabled(rowID == 0)
            }
            if !issue.isEmpty { Text(issue).font(.caption) }
        }.disabled(busy)
    }

    private func selectFirstPart() {
        part = parts.first ?? ""
        rowID = scenes.first?.rowID ?? 0
    }

    private func load() async {
        busy = true; issue = ""
        defer { busy = false }
        do {
            (scripts, rows) = try await appModel.loadGuidedBaserowChoices()
            if !scripts.contains(where: { $0.rowID == scriptID }) { scriptID = scripts.first?.rowID ?? 0 }
            selectFirstPart()
            if scripts.isEmpty { issue = "No Baserow scripts found." }
        } catch { issue = error.localizedDescription }
    }
}
