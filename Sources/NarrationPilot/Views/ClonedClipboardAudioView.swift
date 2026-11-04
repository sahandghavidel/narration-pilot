import KeyboardShortcuts
import SwiftUI

struct ClonedClipboardAudioView: View {
    @ObservedObject var audio: ClonedClipboardAudioController

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                KeyboardShortcuts.Recorder("Prepare & Preview Clipboard", name: .generateClonedClipboardAudio)
                Button(audio.isGenerating ? "Preparing cloned voice…" : "Prepare & Preview Clipboard") {
                    audio.generateClipboard()
                }
                .disabled(audio.isGenerating)
                KeyboardShortcuts.Recorder("Regenerate & Preview Clipboard", name: .regenerateClonedClipboardAudio)
                KeyboardShortcuts.Recorder("Approve Previewed Clipboard Audio", name: .approveClonedClipboardAudio)
                Button("Generate New Version") { audio.generateClipboard(forceNewVersion: true) }
                    .disabled(audio.isGenerating)
                if audio.isGenerating { ProgressView().controlSize(.small) }
                Text(audio.message).font(.caption).textSelection(.enabled)

                if !audio.takes.isEmpty {
                    Picker("Saved narration", selection: Binding(
                        get: { audio.selectedTake?.groupID ?? audio.narrationGroups[0].groupID },
                        set: { audio.selectGroup($0) }
                    )) {
                        ForEach(audio.narrationGroups) { take in
                            Text("\(take.spokenText.prefix(50)) · \(take.voice.name)").tag(take.groupID)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(audio.isGenerating)
                    Picker("Version", selection: Binding(
                        get: { audio.selectedID ?? audio.takes[0].id },
                        set: { audio.select($0) }
                    )) {
                        ForEach(audio.selectedVersions) { take in
                            Text("\(audio.approvedVersions[take.groupID] == take.id ? "✓ Approved · " : "")\(take.label)").tag(take.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(audio.isGenerating)
                    if let take = audio.selectedTake {
                        Text(audio.selectedIsApproved ? "Approved for reuse" : "This version is not approved")
                            .font(.caption).foregroundStyle(audio.selectedIsApproved ? Color.green : Color.secondary)
                        Button(audio.selectedIsApproved ? "Approved" : "Approve Selected Audio") { audio.approveSelected() }
                            .disabled(audio.isGenerating || audio.selectedIsApproved || audio.approvedRecordingIsActive())
                        Text(audio.selectedTranscriptionStatus).font(.caption).textSelection(.enabled)
                        if audio.transcribingIDs.contains(take.id) {
                            ProgressView().controlSize(.small)
                        } else if audio.selectedIsApproved && audio.transcriptions[take.id] == nil {
                            Button(audio.transcriptionErrors[take.id] == nil ? "Create Word Timings" : "Retry Transcription") {
                                audio.transcribeApprovedAudio(take.id)
                            }
                            .disabled(audio.isGenerating)
                        }
                        Text("\(take.voice.name) · \(take.duration.formatted(.number.precision(.fractionLength(1)))) seconds")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(take.spokenText).font(.caption).lineLimit(3).textSelection(.enabled)
                    }
                    HStack {
                        Button("Preview Saved Audio") { Task { await audio.previewSelected() } }
                            .disabled(audio.isGenerating)
                        Button("Stop Preview") { audio.stopPreview() }
                            .disabled(!audio.isPreviewing)
                        Button("Show File") { audio.revealSelected() }
                    }
                }
                Text("The approval shortcut approves the version you previewed only when it matches the current clipboard and selected voice.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Prepare reuses approved audio for matching narration and voice. Otherwise it generates a version. Generate New Version always uses the current clipboard and voice, keeping the existing approval. Preview never starts FocuSee.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Label("Cloned Voice Audio", systemImage: "waveform.badge.plus")
        }
    }
}
