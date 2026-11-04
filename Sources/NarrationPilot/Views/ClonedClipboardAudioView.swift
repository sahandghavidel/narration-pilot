import KeyboardShortcuts
import SwiftUI

struct ClonedClipboardAudioView: View {
    @ObservedObject var audio: ClonedClipboardAudioController

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                KeyboardShortcuts.Recorder("Generate & Preview Clipboard", name: .generateClonedClipboardAudio)
                Button(audio.isGenerating ? "Generating cloned voice…" : "Generate & Preview Clipboard") {
                    audio.generateClipboard()
                }
                .disabled(audio.isGenerating)
                if audio.isGenerating { ProgressView().controlSize(.small) }
                Text(audio.message).font(.caption).textSelection(.enabled)

                if !audio.takes.isEmpty {
                    Picker("Saved version", selection: Binding(
                        get: { audio.selectedID ?? audio.takes[0].id },
                        set: { audio.select($0) }
                    )) {
                        ForEach(audio.takes) { take in
                            Text(take.label).tag(take.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(audio.isGenerating)
                    if let take = audio.selectedTake {
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
                Text("Uses the English voice selected above. Saves every generation as a new version. Preview never starts FocuSee. macOS speech shortcuts keep their current behavior.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Label("Cloned Voice Audio", systemImage: "waveform.badge.plus")
        }
    }
}
