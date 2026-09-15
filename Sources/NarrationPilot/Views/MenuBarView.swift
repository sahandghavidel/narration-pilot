import AppKit
import KeyboardShortcuts
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var inputExpanded = true
    @State private var overlaySettingsExpanded = false
    @State private var speechSettingsExpanded = false
    @State private var shortcutSettingsExpanded = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Narration Pilot")
                    .font(.headline)

                Spacer()

                Text("v\(AppVersion.shortVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(appModel.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            DisclosureGroup("Input", isExpanded: $inputExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Read typed text instead of clipboard", isOn: $appModel.readsTypedTextInsteadOfClipboard)

                    Toggle("Script mode", isOn: $appModel.scriptModeEnabled)

                    if appModel.scriptModeEnabled {
                        Picker("Script format", selection: $appModel.scriptInputFormat) {
                            ForEach(ScriptInputFormat.allCases) { format in
                                Text(format.label).tag(format)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Text(appModel.inputModeStatus)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if appModel.scriptModeEnabled, appModel.scriptInputFormat == .json {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(appModel.loadedChapterDescription ?? "Connect your Notion scenes")
                                .font(.subheadline.bold())
                            SecureField("Notion integration token", text: $appModel.notionToken)
                                .textFieldStyle(.roundedBorder)
                            TextField("Notion data source ID", text: $appModel.notionDataSourceID)
                                .textFieldStyle(.roundedBorder)

                            HStack(spacing: 8) {
                                Button(appModel.isNotionConnected ? "Reconnect" : "Connect Notion") {
                                    appModel.connectNotion()
                                }
                                Button("Sync Now") {
                                    appModel.syncNotionNow()
                                }
                                .disabled(!appModel.hasNotionConfiguration || appModel.isNotionSyncing)
                                Button("Disconnect") {
                                    appModel.disconnectNotion()
                                }
                                .disabled(!appModel.isNotionConnected && appModel.notionToken.isEmpty)
                            }
                            Text(appModel.isNotionConnected ? "Syncs before the Scene Manager opens" : "Share the database with your Notion integration first")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.secondary.opacity(0.08)))
                    } else if appModel.scriptModeEnabled, appModel.scriptInputFormat == .baserow {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(appModel.loadedChapterDescription ?? "Connect your Baserow scenes")
                                .font(.subheadline.bold())
                            TextField("Baserow base URL", text: $appModel.baserowBaseURL)
                                .textFieldStyle(.roundedBorder)
                            SecureField("Baserow database token", text: $appModel.baserowToken)
                                .textFieldStyle(.roundedBorder)
                            TextField("Baserow scenes table ID", text: $appModel.baserowTableID)
                                .textFieldStyle(.roundedBorder)
                            TextField("Baserow scripts table ID", text: $appModel.baserowScriptsTableID)
                                .textFieldStyle(.roundedBorder)

                            if !appModel.baserowScripts.isEmpty {
                                Picker("Script", selection: Binding(
                                    get: { appModel.baserowSelectedScriptID },
                                    set: { appModel.selectBaserowScript($0) }
                                )) {
                                    ForEach(appModel.baserowScripts) { script in
                                        Text(script.title).tag(script.rowID)
                                    }
                                }
                                Picker("Part", selection: Binding(
                                    get: { appModel.baserowPartFilter },
                                    set: { appModel.selectBaserowPart($0) }
                                )) {
                                    Text("All parts").tag("")
                                    ForEach(appModel.baserowPartOptions, id: \.self) { part in
                                        Text(part).tag(part)
                                    }
                                }
                            }

                            HStack(spacing: 8) {
                                Button(appModel.isBaserowConnected ? "Reconnect" : "Connect Baserow") {
                                    appModel.connectBaserow()
                                }
                                Button("Sync Now") {
                                    appModel.syncBaserowNow()
                                }
                                .disabled(!appModel.hasBaserowConfiguration || appModel.isBaserowSyncing)
                                Button("Disconnect") {
                                    appModel.disconnectBaserow()
                                }
                                .disabled(!appModel.isBaserowConnected && appModel.baserowToken.isEmpty)
                            }
                            Text(appModel.isBaserowConnected ? "Syncs before the Scene Manager opens" : "Use a database token with read and update access")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.secondary.opacity(0.08)))
                    } else {
                        TextEditor(text: $appModel.typedText)
                            .font(.body)
                            .frame(height: 110)
                            .onChange(of: appModel.typedText) {
                                appModel.refreshScriptScenes()
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.25))
                            )
                    }

                    HStack(spacing: 8) {
                        Button(appModel.readButtonTitle) {
                            appModel.readNow()
                        }

                        if !(appModel.scriptModeEnabled && appModel.scriptInputFormat.usesStructuredScenes) {
                            Button("Clear") {
                                appModel.clearTypedText()
                            }
                            .disabled(appModel.typedText.isEmpty)
                        }
                    }
                }
                .padding(.top, 6)
            }

            if appModel.scriptModeEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    Text(appModel.scriptSceneProgress)
                        .font(.subheadline.bold())

                    if let title = appModel.currentSceneTitle {
                        Text(title)
                            .font(.caption.bold())
                    }

                    if let part = appModel.currentScenePart {
                        Text(part)
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }

                    if let onScreen = appModel.currentSceneOnScreenSummary {
                        Text("On screen: \(onScreen)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Text(appModel.currentSceneText ?? (appModel.scriptInputFormat.usesStructuredScenes ? "Connect or sync a scene source to load scenes." : "Paste a script to create scenes."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 8) {

                        Button("Previous") {
                            appModel.goToPreviousScene()
                        }
                        .disabled(!appModel.canGoToPreviousScene)

                        Button("Replay") {
                            appModel.replayCurrentScriptScene()
                        }
                        .disabled(appModel.currentSceneText == nil)

                        Button("Next") {
                            appModel.goToNextScene()
                        }
                        .disabled(!appModel.canGoToNextScene)

                        Button("Restart") {
                            appModel.restartScript()
                        }
                        .disabled(appModel.currentSceneText == nil)
                    }
                }

                Toggle("Show presenter overlay", isOn: $appModel.showPresenterOverlay)

                DisclosureGroup("Presenter overlay settings", isExpanded: $overlaySettingsExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                                Toggle("Hide overlay from screen recordings", isOn: $appModel.hidePresenterOverlayFromCapture)
                                    .disabled(!appModel.showPresenterOverlay)

                                Toggle("Hide overlay while audio is playing", isOn: $appModel.hidePresenterOverlayWhileSpeaking)
                                    .disabled(!appModel.showPresenterOverlay)

                                overlaySlider(
                                    "Opacity",
                                    value: $appModel.presenterOverlayOpacity,
                                    range: AppModel.minPresenterOverlayOpacity...AppModel.maxPresenterOverlayOpacity,
                                    specifier: "%.2f"
                                )
                                overlaySlider(
                                    "Width",
                                    value: $appModel.presenterOverlayWidth,
                                    range: AppModel.minPresenterOverlayWidth...AppModel.maxPresenterOverlayWidth,
                                    specifier: "%.0f"
                                )
                                overlaySlider(
                                    "Height",
                                    value: $appModel.presenterOverlayHeight,
                                    range: AppModel.minPresenterOverlayHeight...AppModel.maxPresenterOverlayHeight,
                                    specifier: "%.0f"
                                )
                                overlaySlider(
                                    "Bottom position",
                                    value: $appModel.presenterOverlayBottomOffset,
                                    range: AppModel.minPresenterOverlayBottomOffset...AppModel.maxPresenterOverlayBottomOffset,
                                    specifier: "%.0f"
                                )
                                overlaySlider(
                                    "Horizontal position",
                                    value: $appModel.presenterOverlayHorizontalOffset,
                                    range: AppModel.minPresenterOverlayHorizontalOffset...AppModel.maxPresenterOverlayHorizontalOffset,
                                    specifier: "%.0f"
                                )
                                overlaySlider(
                                    "Current text size",
                                    value: $appModel.presenterOverlayCurrentFontSize,
                                    range: AppModel.minPresenterOverlayCurrentFontSize...AppModel.maxPresenterOverlayCurrentFontSize,
                                    specifier: "%.0f"
                                )
                                overlaySlider(
                                    "Previous/next text size",
                                    value: $appModel.presenterOverlaySideFontSize,
                                    range: AppModel.minPresenterOverlaySideFontSize...AppModel.maxPresenterOverlaySideFontSize,
                                    specifier: "%.0f"
                                )
                                overlaySlider(
                                    "Current text opacity",
                                    value: $appModel.presenterOverlayCurrentTextOpacity,
                                    range: AppModel.minPresenterOverlayTextOpacity...AppModel.maxPresenterOverlayTextOpacity,
                                    specifier: "%.2f"
                                )
                                overlaySlider(
                                    "Previous/next text opacity",
                                    value: $appModel.presenterOverlaySecondaryTextOpacity,
                                    range: AppModel.minPresenterOverlayTextOpacity...AppModel.maxPresenterOverlayTextOpacity,
                                    specifier: "%.2f"
                                )

                                ColorPicker(
                                    "Current text color",
                                    selection: $appModel.presenterOverlayCurrentTextColor,
                                    supportsOpacity: true
                                )

                                colorPresetRow(for: $appModel.presenterOverlayCurrentTextColor)

                                ColorPicker(
                                    "Previous/next text color",
                                    selection: $appModel.presenterOverlaySecondaryTextColor,
                                    supportsOpacity: true
                                )

                                colorPresetRow(for: $appModel.presenterOverlaySecondaryTextColor)

                                Button("Reset overlay defaults") {
                                    appModel.resetPresenterOverlayDefaults()
                                }
                    }
                    .padding(.top, 6)
                }
            }

            HStack(spacing: 8) {

                Button("Stop") {
                    appModel.stopReading()
                }

                Button(appModel.speechState.pauseResumeTitle) {
                    appModel.togglePauseResume()
                }
                .disabled(appModel.speechState == .idle || appModel.speechState == .stopping)
            }

            DisclosureGroup("Speech settings", isExpanded: $speechSettingsExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Read Speed: \(appModel.speedMultiplier, specifier: "%.2f")x")
                        .font(.subheadline)

                    Slider(
                        value: $appModel.speedMultiplier,
                        in: SpeechRateMapper.minMultiplier...SpeechRateMapper.maxMultiplier,
                        step: 0.05
                    )

                    Text("Using: \(appModel.outputVoiceDescription)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let note = appModel.outputVoiceNote {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }

                    Picker(
                        "Voice",
                        selection: Binding(
                            get: { appModel.selectedVoiceIdentifierForPicker },
                            set: { appModel.updateVoiceSelection($0) }
                        )
                    ) {
                        Text("System Default").tag("")
                        ForEach(appModel.availableVoices, id: \.identifier) { voice in
                            Text("\(voice.name) (\(voice.language))")
                                .tag(voice.identifier)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(.top, 6)
            }

            DisclosureGroup("Global shortcuts", isExpanded: $shortcutSettingsExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                readShortcutSettings(
                    title: "Read Current Input 1",
                    name: .readClipboard,
                    speedMultiplier: $appModel.readShortcutOneSpeedMultiplier,
                    actionBefore: $appModel.readShortcutOneActionBefore,
                    actionAfter: $appModel.readShortcutOneActionAfter,
                    delayBefore: $appModel.readShortcutOneDelayBefore,
                    delayAfter: $appModel.readShortcutOneDelayAfter,
                    waitsForNeonSpotlight: $appModel.readShortcutOneWaitsForNeonSpotlight,
                    waitsForUserInactivity: $appModel.readShortcutOneWaitsForUserInactivity
                )

                Divider()

                readShortcutSettings(
                    title: "Read Current Input 2",
                    name: .readCurrentInputSecondary,
                    speedMultiplier: $appModel.readShortcutTwoSpeedMultiplier,
                    actionBefore: $appModel.readShortcutTwoActionBefore,
                    actionAfter: $appModel.readShortcutTwoActionAfter,
                    delayBefore: $appModel.readShortcutTwoDelayBefore,
                    delayAfter: $appModel.readShortcutTwoDelayAfter,
                    waitsForNeonSpotlight: $appModel.readShortcutTwoWaitsForNeonSpotlight,
                    waitsForUserInactivity: $appModel.readShortcutTwoWaitsForUserInactivity
                )

                Divider()

                readShortcutSettings(
                    title: "Read Clipboard Always 1",
                    name: .readClipboardAlways,
                    speedMultiplier: $appModel.readClipboardAlwaysSpeedMultiplier,
                    actionBefore: $appModel.readClipboardAlwaysActionBefore,
                    actionAfter: $appModel.readClipboardAlwaysActionAfter,
                    delayBefore: $appModel.readClipboardAlwaysDelayBefore,
                    delayAfter: $appModel.readClipboardAlwaysDelayAfter,
                    waitsForNeonSpotlight: $appModel.readClipboardAlwaysWaitsForNeonSpotlight,
                    waitsForUserInactivity: $appModel.readClipboardAlwaysWaitsForUserInactivity
                )

                Divider()

                readShortcutSettings(
                    title: "Read Clipboard Always 2",
                    name: .readClipboardAlwaysSecondary,
                    speedMultiplier: $appModel.readClipboardAlwaysTwoSpeedMultiplier,
                    actionBefore: $appModel.readClipboardAlwaysTwoActionBefore,
                    actionAfter: $appModel.readClipboardAlwaysTwoActionAfter,
                    delayBefore: $appModel.readClipboardAlwaysTwoDelayBefore,
                    delayAfter: $appModel.readClipboardAlwaysTwoDelayAfter,
                    waitsForNeonSpotlight: $appModel.readClipboardAlwaysTwoWaitsForNeonSpotlight,
                    waitsForUserInactivity: $appModel.readClipboardAlwaysTwoWaitsForUserInactivity
                )

                Divider()

                readShortcutSettings(
                    title: "Read Clipboard Always 3",
                    name: .readClipboardAlwaysTertiary,
                    speedMultiplier: $appModel.readClipboardAlwaysThreeSpeedMultiplier,
                    actionBefore: $appModel.readClipboardAlwaysThreeActionBefore,
                    actionAfter: $appModel.readClipboardAlwaysThreeActionAfter,
                    delayBefore: $appModel.readClipboardAlwaysThreeDelayBefore,
                    delayAfter: $appModel.readClipboardAlwaysThreeDelayAfter,
                    waitsForNeonSpotlight: $appModel.readClipboardAlwaysThreeWaitsForNeonSpotlight,
                    waitsForUserInactivity: $appModel.readClipboardAlwaysThreeWaitsForUserInactivity
                )

                Text("Ignores typed-text mode and Script mode.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Divider()

                DisclosureGroup("External trigger shortcut") {
                    VStack(alignment: .leading, spacing: 8) {
                        TriggerShortcutCaptureView()

                        Text("Use FocuSee's existing Pause/Continue Recording shortcut. State-aware actions inspect FocuSee before sending it.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        KeyboardShortcuts.Recorder(
                            "Ensure FocuSee Recording",
                            name: .ensureFocuSeeRecording
                        )
                        KeyboardShortcuts.Recorder(
                            "Ensure FocuSee Paused",
                            name: .ensureFocuSeePaused
                        )

                        Text(appModel.isShortcutTriggerAccessibilityTrusted ? "Accessibility permission granted." : "Accessibility permission required to trigger external shortcuts.")
                            .font(.caption2)
                            .foregroundStyle(appModel.isShortcutTriggerAccessibilityTrusted ? Color.secondary : Color.orange)

                        HStack(spacing: 8) {
                            Button("Open Accessibility Settings") {
                                appModel.openShortcutTriggerAccessibilitySettings()
                            }

                            Button("Request Permission") {
                                appModel.requestShortcutTriggerAccessibilityPermission()
                            }
                        }

                        Stepper(
                            "Input idle period: \(appModel.userActivityIdlePeriod, specifier: "%.1f") seconds",
                            value: $appModel.userActivityIdlePeriod,
                            in: UserActivityIdlePolicy.minimumIdlePeriod...UserActivityIdlePolicy.maximumIdlePeriod,
                            step: 0.1
                        )
                        .font(.caption)

                        Stepper(
                            "Maximum input wait: \(appModel.userActivityMaximumWait, specifier: "%.0f") seconds",
                            value: $appModel.userActivityMaximumWait,
                            in: UserActivityIdlePolicy.minimumMaximumWait...UserActivityIdlePolicy.maximumMaximumWait,
                            step: 1
                        )
                        .font(.caption)

                        Text("Input monitoring observes only activity categories; it does not store keys or typed text.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Divider()

                        Toggle("Enable recording cue sounds", isOn: $appModel.recordingCueSoundsEnabled)

                        HStack {
                            Picker("Start sound", selection: $appModel.recordingStartCueSound) {
                                ForEach(RecordingCueSound.allCases) { sound in
                                    Text(sound.title).tag(sound)
                                }
                            }
                            .pickerStyle(.menu)

                            Button("Test") {
                                appModel.previewRecordingCueSound(appModel.recordingStartCueSound)
                            }
                        }
                        .disabled(!appModel.recordingCueSoundsEnabled)

                        Stepper(
                            "Sound before recording: \(appModel.recordingStartCueDelay, specifier: "%.1f") seconds",
                            value: $appModel.recordingStartCueDelay,
                            in: AppModel.minRecordingStartCueDelay...AppModel.maxRecordingStartCueDelay,
                            step: 0.1
                        )
                        .font(.caption)
                        .disabled(!appModel.recordingCueSoundsEnabled || appModel.recordingStartCueSound == .none)

                        HStack {
                            Picker("Stop sound", selection: $appModel.recordingStopCueSound) {
                                ForEach(RecordingCueSound.allCases) { sound in
                                    Text(sound.title).tag(sound)
                                }
                            }
                            .pickerStyle(.menu)

                            Button("Test") {
                                appModel.previewRecordingCueSound(appModel.recordingStopCueSound)
                            }
                        }
                        .disabled(!appModel.recordingCueSoundsEnabled)

                        Stepper(
                            "Sound after recording pauses: \(appModel.recordingStopCueDelay, specifier: "%.1f") seconds",
                            value: $appModel.recordingStopCueDelay,
                            in: AppModel.minRecordingStopCueDelay...AppModel.maxRecordingStopCueDelay,
                            step: 0.1
                        )
                        .font(.caption)
                        .disabled(!appModel.recordingCueSoundsEnabled || appModel.recordingStopCueSound == .none)

                        HStack {
                            Picker("Failure sound", selection: $appModel.recordingFailureCueSound) {
                                ForEach(RecordingFailureCueSound.allCases) { sound in
                                    Text(sound.title).tag(sound)
                                }
                            }
                            .pickerStyle(.menu)

                            Button("Test") {
                                appModel.previewRecordingFailureCueSound()
                            }
                        }
                        .disabled(!appModel.recordingCueSoundsEnabled)

                        Text("Cue sounds run only with verified Ensure FocuSee Recording/Paused actions. Narration is cancelled if recording fails to start.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                    }
                    .padding(.top, 6)
                }

                Divider()

                DisclosureGroup("Playback and scene shortcuts") {
                    VStack(alignment: .leading, spacing: 8) {
                        KeyboardShortcuts.Recorder("Stop Reading", name: .stopReading)
                        KeyboardShortcuts.Recorder("Pause / Resume", name: .pauseResumeReading)
                        KeyboardShortcuts.Recorder("Replay Scene", name: .replayScriptScene)
                        KeyboardShortcuts.Recorder("Replay On Screen Only", name: .replayOnScreenOnly)
                        KeyboardShortcuts.Recorder("Replay Code Only", name: .replayCodeOnly)
                        KeyboardShortcuts.Recorder("Previous Scene", name: .previousScriptScene)
                        KeyboardShortcuts.Recorder("Next Scene", name: .nextScriptScene)
                        KeyboardShortcuts.Recorder("Restart Script", name: .restartScript)
                        KeyboardShortcuts.Recorder("Toggle Overlay", name: .togglePresenterOverlay)
                        KeyboardShortcuts.Recorder("Edit Current Scene", name: .editCurrentScene)
                    }
                    .padding(.top, 6)
                }
                }
                .padding(.top, 6)
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 460, height: 720)
    }

    private func readShortcutSettings(
        title: String,
        name: KeyboardShortcuts.Name,
        speedMultiplier: Binding<Double>,
        actionBefore: Binding<ExternalTriggerAction>,
        actionAfter: Binding<ExternalTriggerAction>,
        delayBefore: Binding<Double>,
        delayAfter: Binding<Double>,
        waitsForNeonSpotlight: Binding<Bool>,
        waitsForUserInactivity: Binding<Bool>
    ) -> some View {
        DisclosureGroup(title) {
            VStack(alignment: .leading, spacing: 6) {
                KeyboardShortcuts.Recorder("Shortcut", name: name)

                Text("Speech Speed: \(speedMultiplier.wrappedValue, specifier: "%.2f")x")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Slider(
                    value: speedMultiplier,
                    in: SpeechRateMapper.minMultiplier...SpeechRateMapper.maxMultiplier,
                    step: 0.05
                )

                externalTriggerActionPicker("Before reading", selection: actionBefore)
                triggerDelayStepper("Delay before speech", value: delayBefore)
                    .disabled(actionBefore.wrappedValue == .none)

                externalTriggerActionPicker("After reading", selection: actionAfter)
                triggerDelayStepper("Delay after speech", value: delayAfter)
                    .disabled(actionAfter.wrappedValue == .none)

                Toggle(
                    "Wait for Neon Spotlight before pausing FocuSee",
                    isOn: waitsForNeonSpotlight
                )
                .font(.caption)
                .disabled(actionAfter.wrappedValue != .ensurePaused)

                if waitsForNeonSpotlight.wrappedValue,
                   actionAfter.wrappedValue == .ensurePaused {
                    Text("Waits for every visible highlight and fade-out, with a 10-second safety timeout.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Toggle(
                    "Wait until mouse and keyboard are idle",
                    isOn: waitsForUserInactivity
                )
                .font(.caption)
                .disabled(actionAfter.wrappedValue != .ensurePaused)
            }
            .padding(.top, 6)
        }
    }

    private func externalTriggerActionPicker(
        _ title: String,
        selection: Binding<ExternalTriggerAction>
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(ExternalTriggerAction.allCases) { action in
                Text(action.title).tag(action)
            }
        }
        .pickerStyle(.menu)
        .font(.caption)
    }

    private func triggerDelayStepper(_ title: String, value: Binding<Double>) -> some View {
        Stepper(
            "\(title): \(value.wrappedValue, specifier: "%.1f") seconds",
            value: value,
            in: AppModel.minTriggerDelay...AppModel.maxTriggerDelay,
            step: 0.1
        )
        .font(.caption)
    }

    private func overlaySlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        specifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title): \(value.wrappedValue, specifier: specifier)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Slider(value: value, in: range)
        }
    }

    private func colorPresetRow(for color: Binding<Color>) -> some View {
        HStack(spacing: 8) {
            colorPreset(.white, selection: color)
            colorPreset(.yellow, selection: color)
            colorPreset(.green, selection: color)
            colorPreset(.cyan, selection: color)
            colorPreset(.orange, selection: color)
            colorPreset(.red, selection: color)
        }
    }

    private func colorPreset(_ color: Color, selection: Binding<Color>) -> some View {
        Button {
            selection.wrappedValue = color
        } label: {
            Circle()
                .fill(color)
                .frame(width: 18, height: 18)
                .overlay(Circle().stroke(.secondary.opacity(0.4)))
        }
        .buttonStyle(.plain)
    }
}
