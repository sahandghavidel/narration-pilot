import SwiftUI

struct UltimateEditorVoiceView: View {
    @StateObject private var library = UltimateEditorVoiceLibrary()

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Picker("English voice", selection: Binding(
                    get: { library.selectedID },
                    set: { library.select($0) }
                )) {
                    Text("Choose a voice…").tag("")
                    if let saved = library.selectedVoice,
                       !library.voices.contains(where: { $0.id == saved.id }) {
                        Text("\(saved.name) (saved)").tag(saved.id)
                    }
                    ForEach(library.voices) { voice in
                        Text("\(voice.name) · \(voice.engineLabel)").tag(voice.id)
                    }
                }
                .pickerStyle(.menu)
                .disabled(library.isLoading)

                if let voice = library.selectedVoice {
                    Text("Saved voice: \(voice.name)")
                        .font(.caption)
                }

                HStack(alignment: .top, spacing: 8) {
                    if library.isLoading {
                        ProgressView().controlSize(.small)
                        Text("Loading English voices…")
                    } else {
                        Text(library.message)
                            .foregroundStyle(library.connectionFailed ? Color.orange : Color.secondary)
                    }
                    Spacer(minLength: 0)
                    Button("Refresh") {
                        Task { await library.refresh() }
                    }
                    .disabled(library.isLoading)
                }
                .font(.caption)

                if library.selectionUnavailable {
                    Text("The saved voice is no longer in the enabled English list. Choose another voice or re-enable it in Ultimate Video Editor.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Text("Used by Cloned Voice Audio below. Existing macOS playback uses the voice in Speech settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Label("Ultimate Video Editor voice", systemImage: "waveform")
        }
        .task { await library.refresh() }
    }
}
