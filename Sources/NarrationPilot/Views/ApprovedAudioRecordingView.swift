import KeyboardShortcuts
import SwiftUI

struct ApprovedAudioRecordingView: View {
    @ObservedObject var recording: ApprovedAudioRecordingSession
    let record: () -> Void
    @State private var settingsExpanded = true

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button("Record Approved Clipboard Audio", action: record).disabled(recording.isBusy)
                    Button("Stop Cloned Take") { recording.cancel() }.disabled(!recording.isBusy)
                }
                Text(recording.message).font(.caption).textSelection(.enabled)
                if recording.duration > 0 {
                    Text("Elapsed: \(recording.elapsed, specifier: "%.1f")s · Remaining: \(recording.remaining, specifier: "%.1f")s · Total: \(recording.duration, specifier: "%.1f")s")
                        .font(.caption).monospacedDigit()
                    ProgressView(value: recording.elapsed, total: recording.duration)
                }
                DisclosureGroup("Recording shortcut settings", isExpanded: $settingsExpanded) {
                    VStack(alignment: .leading, spacing: 6) {
                        KeyboardShortcuts.Recorder("Shortcut", name: .recordApprovedClipboardAudio)
                        Text("Approved WAV · original playback speed (1.00x)").font(.caption).foregroundStyle(.secondary)
                        actionPicker("Before playback", selection: $recording.settings.before)
                        delayStepper("Delay before playback", value: $recording.settings.delayBefore)
                            .disabled(recording.settings.before == .none)
                        actionPicker("After playback", selection: $recording.settings.after)
                        delayStepper("Delay after playback", value: $recording.settings.delayAfter)
                            .disabled(recording.settings.after == .none)
                        Toggle("Wait for Neon Spotlight before pausing FocuSee", isOn: $recording.settings.waitsForNeon)
                            .disabled(recording.settings.after != .ensurePaused)
                        Toggle("Wait until mouse and keyboard are idle", isOn: $recording.settings.waitsForInputIdle)
                            .disabled(recording.settings.after != .ensurePaused)
                        if recording.settings.waitsForInputIdle && recording.settings.after == .ensurePaused {
                            Stepper("Mouse/activity quiet period: \(recording.settings.quietPeriod, specifier: "%.1f") seconds",
                                    value: $recording.settings.quietPeriod, in: 0.1...5, step: 0.1)
                            Stepper("Keyboard quiet period: \(recording.settings.keyboardQuietPeriod, specifier: "%.1f") seconds",
                                    value: $recording.settings.keyboardQuietPeriod, in: 0.1...5, step: 0.1)
                            Stepper("Maximum extra idle wait: \(recording.settings.maximumExtraWait, specifier: "%.1f") seconds",
                                    value: $recording.settings.maximumExtraWait, in: 1...30, step: 1)
                        }
                        Text("Activity is tracked during playback. If already quiet when the WAV ends, there is no extra idle delay. Any after-playback delay or Neon Spotlight wait still applies.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .disabled(recording.isBusy)
                    .padding(.top, 6)
                }
                Text("Copy narration that already has approved audio for the voice selected above. Uses the local WAV; never generates audio, waits for transcription, or advances scenes. FocuSee must already have an active session for verified resume/pause actions.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Label("Approved Audio Recording", systemImage: "record.circle")
        }
    }

    private func actionPicker(_ title: String, selection: Binding<ExternalTriggerAction>) -> some View {
        Picker(title, selection: selection) {
            ForEach(ExternalTriggerAction.allCases) { action in Text(action.title).tag(action) }
        }.pickerStyle(.menu)
    }

    private func delayStepper(_ title: String, value: Binding<Double>) -> some View {
        Stepper("\(title): \(value.wrappedValue, specifier: "%.1f") seconds", value: value, in: 0...10, step: 0.1)
    }
}
