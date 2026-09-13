import AVFoundation
import Combine
import Foundation
import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var speechState: SpeechState = .idle
    @Published var statusMessage: String = SpeechState.idle.label
    @Published private(set) var outputVoiceDescription: String = "System Default"
    @Published private(set) var outputVoiceNote: String?
    @Published private(set) var isShortcutTriggerAccessibilityTrusted: Bool
    @Published private(set) var recordingTriggerShortcut: TriggerShortcut?
    @Published var typedText: String = ""
    @Published var scriptInputFormat: ScriptInputFormat {
        didSet {
            defaults.set(scriptInputFormat.rawValue, forKey: Self.scriptInputFormatKey)
            if scriptInputFormat.usesStructuredScenes {
                readsTypedTextInsteadOfClipboard = true
                scriptModeEnabled = true
            }
            currentSceneIndex = 0
            refreshScriptScenes()
            presenterOverlayController?.updateLayout()
        }
    }
    @Published private(set) var loadedChapter: NarrationChapter?
    @Published private(set) var loadedChapterURL: URL?
    @Published var notionToken: String
    @Published var notionDataSourceID: String
    @Published private(set) var isNotionConnected = false
    @Published private(set) var isNotionSyncing = false
    @Published var baserowBaseURL: String
    @Published var baserowToken: String
    @Published var baserowTableID: String
    @Published var baserowScriptsTableID: String
    @Published var baserowSelectedScriptID: Int {
        didSet { defaults.set(baserowSelectedScriptID, forKey: Self.baserowSelectedScriptIDKey) }
    }
    @Published var baserowPartFilter: String {
        didSet { defaults.set(baserowPartFilter, forKey: Self.baserowPartFilterKey) }
    }
    @Published private(set) var isBaserowConnected = false
    @Published private(set) var isBaserowSyncing = false
    @Published private(set) var baserowScripts: [BaserowScriptRecord] = []
    @Published private(set) var baserowPartOptions: [String] = []
    @Published private(set) var baserowUndoActionName: String?
    @Published private(set) var isUndoingBaserowOperation = false
    @Published private(set) var isSceneManagerNarrationQueuePlaying = false
    @Published private(set) var sceneManagerNarrationSceneID: String?

    @Published var recordingCueSoundsEnabled: Bool {
        didSet { defaults.set(recordingCueSoundsEnabled, forKey: Self.recordingCueSoundsEnabledKey) }
    }
    @Published var recordingStartCueSound: RecordingCueSound {
        didSet { defaults.set(recordingStartCueSound.rawValue, forKey: Self.recordingStartCueSoundKey) }
    }
    @Published var recordingStopCueSound: RecordingCueSound {
        didSet { defaults.set(recordingStopCueSound.rawValue, forKey: Self.recordingStopCueSoundKey) }
    }
    @Published var recordingFailureCueSound: RecordingFailureCueSound {
        didSet { defaults.set(recordingFailureCueSound.rawValue, forKey: Self.recordingFailureCueSoundKey) }
    }
    @Published var recordingStartCueDelay: Double {
        didSet { defaults.set(Self.clampRecordingStartCueDelay(recordingStartCueDelay), forKey: Self.recordingStartCueDelayKey) }
    }
    @Published var recordingStopCueDelay: Double {
        didSet { defaults.set(Self.clampRecordingStopCueDelay(recordingStopCueDelay), forKey: Self.recordingStopCueDelayKey) }
    }

    @Published var readShortcutOneDelayBefore: Double {
        didSet { persistTriggerDelay(readShortcutOneDelayBefore, key: Self.readShortcutOneDelayBeforeKey) }
    }
    @Published var readShortcutOneDelayAfter: Double {
        didSet { persistTriggerDelay(readShortcutOneDelayAfter, key: Self.readShortcutOneDelayAfterKey) }
    }
    @Published var readShortcutTwoDelayBefore: Double {
        didSet { persistTriggerDelay(readShortcutTwoDelayBefore, key: Self.readShortcutTwoDelayBeforeKey) }
    }
    @Published var readShortcutTwoDelayAfter: Double {
        didSet { persistTriggerDelay(readShortcutTwoDelayAfter, key: Self.readShortcutTwoDelayAfterKey) }
    }
    @Published var readClipboardAlwaysDelayBefore: Double {
        didSet { persistTriggerDelay(readClipboardAlwaysDelayBefore, key: Self.readClipboardAlwaysDelayBeforeKey) }
    }
    @Published var readClipboardAlwaysDelayAfter: Double {
        didSet { persistTriggerDelay(readClipboardAlwaysDelayAfter, key: Self.readClipboardAlwaysDelayAfterKey) }
    }
    @Published var readClipboardAlwaysTwoDelayBefore: Double {
        didSet { persistTriggerDelay(readClipboardAlwaysTwoDelayBefore, key: Self.readClipboardAlwaysTwoDelayBeforeKey) }
    }
    @Published var readClipboardAlwaysTwoDelayAfter: Double {
        didSet { persistTriggerDelay(readClipboardAlwaysTwoDelayAfter, key: Self.readClipboardAlwaysTwoDelayAfterKey) }
    }
    @Published var readClipboardAlwaysThreeDelayBefore: Double {
        didSet { persistTriggerDelay(readClipboardAlwaysThreeDelayBefore, key: Self.readClipboardAlwaysThreeDelayBeforeKey) }
    }
    @Published var readClipboardAlwaysThreeDelayAfter: Double {
        didSet { persistTriggerDelay(readClipboardAlwaysThreeDelayAfter, key: Self.readClipboardAlwaysThreeDelayAfterKey) }
    }

    @Published var readShortcutOneWaitsForNeonSpotlight: Bool {
        didSet { defaults.set(readShortcutOneWaitsForNeonSpotlight, forKey: Self.readShortcutOneWaitsForNeonSpotlightKey) }
    }
    @Published var readShortcutTwoWaitsForNeonSpotlight: Bool {
        didSet { defaults.set(readShortcutTwoWaitsForNeonSpotlight, forKey: Self.readShortcutTwoWaitsForNeonSpotlightKey) }
    }
    @Published var readClipboardAlwaysWaitsForNeonSpotlight: Bool {
        didSet { defaults.set(readClipboardAlwaysWaitsForNeonSpotlight, forKey: Self.readClipboardAlwaysWaitsForNeonSpotlightKey) }
    }
    @Published var readClipboardAlwaysTwoWaitsForNeonSpotlight: Bool {
        didSet { defaults.set(readClipboardAlwaysTwoWaitsForNeonSpotlight, forKey: Self.readClipboardAlwaysTwoWaitsForNeonSpotlightKey) }
    }
    @Published var readClipboardAlwaysThreeWaitsForNeonSpotlight: Bool {
        didSet { defaults.set(readClipboardAlwaysThreeWaitsForNeonSpotlight, forKey: Self.readClipboardAlwaysThreeWaitsForNeonSpotlightKey) }
    }
    @Published var readShortcutOneWaitsForUserInactivity: Bool {
        didSet { defaults.set(readShortcutOneWaitsForUserInactivity, forKey: Self.readShortcutOneWaitsForUserInactivityKey) }
    }
    @Published var readShortcutTwoWaitsForUserInactivity: Bool {
        didSet { defaults.set(readShortcutTwoWaitsForUserInactivity, forKey: Self.readShortcutTwoWaitsForUserInactivityKey) }
    }
    @Published var readClipboardAlwaysWaitsForUserInactivity: Bool {
        didSet { defaults.set(readClipboardAlwaysWaitsForUserInactivity, forKey: Self.readClipboardAlwaysWaitsForUserInactivityKey) }
    }
    @Published var readClipboardAlwaysTwoWaitsForUserInactivity: Bool {
        didSet { defaults.set(readClipboardAlwaysTwoWaitsForUserInactivity, forKey: Self.readClipboardAlwaysTwoWaitsForUserInactivityKey) }
    }
    @Published var readClipboardAlwaysThreeWaitsForUserInactivity: Bool {
        didSet { defaults.set(readClipboardAlwaysThreeWaitsForUserInactivity, forKey: Self.readClipboardAlwaysThreeWaitsForUserInactivityKey) }
    }
    @Published var userActivityIdlePeriod: Double {
        didSet {
            let clamped = UserActivityIdlePolicy.clampedIdlePeriod(userActivityIdlePeriod)
            if clamped != userActivityIdlePeriod {
                userActivityIdlePeriod = clamped
                return
            }
            defaults.set(clamped, forKey: Self.userActivityIdlePeriodKey)
        }
    }
    @Published var userActivityMaximumWait: Double {
        didSet {
            let clamped = UserActivityIdlePolicy.clampedMaximumWait(userActivityMaximumWait)
            if clamped != userActivityMaximumWait {
                userActivityMaximumWait = clamped
                return
            }
            defaults.set(clamped, forKey: Self.userActivityMaximumWaitKey)
        }
    }

    @Published var readShortcutOneActionBefore: ExternalTriggerAction {
        didSet {
            persistExternalTriggerAction(
                readShortcutOneActionBefore,
                actionKey: Self.readShortcutOneActionBeforeKey,
                legacyBoolKey: Self.readShortcutOneTriggerBeforeKey
            )
            refreshShortcutTriggerAccessibilityStatus()
        }
    }

    @Published var readShortcutOneActionAfter: ExternalTriggerAction {
        didSet {
            persistExternalTriggerAction(
                readShortcutOneActionAfter,
                actionKey: Self.readShortcutOneActionAfterKey,
                legacyBoolKey: Self.readShortcutOneTriggerAfterKey
            )
            refreshShortcutTriggerAccessibilityStatus()
        }
    }

    @Published var readShortcutOneSpeedMultiplier: Double {
        didSet {
            let clamped = SpeechRateMapper.clampMultiplier(readShortcutOneSpeedMultiplier)
            if clamped != readShortcutOneSpeedMultiplier {
                readShortcutOneSpeedMultiplier = clamped
                return
            }

            defaults.set(clamped, forKey: Self.readShortcutOneSpeedKey)
        }
    }

    @Published var readShortcutTwoActionBefore: ExternalTriggerAction {
        didSet {
            persistExternalTriggerAction(
                readShortcutTwoActionBefore,
                actionKey: Self.readShortcutTwoActionBeforeKey,
                legacyBoolKey: Self.readShortcutTwoTriggerBeforeKey
            )
            refreshShortcutTriggerAccessibilityStatus()
        }
    }

    @Published var readShortcutTwoActionAfter: ExternalTriggerAction {
        didSet {
            persistExternalTriggerAction(
                readShortcutTwoActionAfter,
                actionKey: Self.readShortcutTwoActionAfterKey,
                legacyBoolKey: Self.readShortcutTwoTriggerAfterKey
            )
            refreshShortcutTriggerAccessibilityStatus()
        }
    }

    @Published var readShortcutTwoSpeedMultiplier: Double {
        didSet {
            let clamped = SpeechRateMapper.clampMultiplier(readShortcutTwoSpeedMultiplier)
            if clamped != readShortcutTwoSpeedMultiplier {
                readShortcutTwoSpeedMultiplier = clamped
                return
            }

            defaults.set(clamped, forKey: Self.readShortcutTwoSpeedKey)
        }
    }

    @Published var readClipboardAlwaysActionBefore: ExternalTriggerAction {
        didSet {
            persistExternalTriggerAction(
                readClipboardAlwaysActionBefore,
                actionKey: Self.readClipboardAlwaysActionBeforeKey,
                legacyBoolKey: Self.readClipboardAlwaysTriggerBeforeKey
            )
            refreshShortcutTriggerAccessibilityStatus()
        }
    }

    @Published var readClipboardAlwaysActionAfter: ExternalTriggerAction {
        didSet {
            persistExternalTriggerAction(
                readClipboardAlwaysActionAfter,
                actionKey: Self.readClipboardAlwaysActionAfterKey,
                legacyBoolKey: Self.readClipboardAlwaysTriggerAfterKey
            )
            refreshShortcutTriggerAccessibilityStatus()
        }
    }

    @Published var readClipboardAlwaysSpeedMultiplier: Double {
        didSet {
            let clamped = SpeechRateMapper.clampMultiplier(readClipboardAlwaysSpeedMultiplier)
            if clamped != readClipboardAlwaysSpeedMultiplier {
                readClipboardAlwaysSpeedMultiplier = clamped
                return
            }

            defaults.set(clamped, forKey: Self.readClipboardAlwaysSpeedKey)
        }
    }

    @Published var readClipboardAlwaysTwoActionBefore: ExternalTriggerAction {
        didSet {
            persistExternalTriggerAction(
                readClipboardAlwaysTwoActionBefore,
                actionKey: Self.readClipboardAlwaysTwoActionBeforeKey,
                legacyBoolKey: Self.readClipboardAlwaysTwoTriggerBeforeKey
            )
            refreshShortcutTriggerAccessibilityStatus()
        }
    }

    @Published var readClipboardAlwaysTwoActionAfter: ExternalTriggerAction {
        didSet {
            persistExternalTriggerAction(
                readClipboardAlwaysTwoActionAfter,
                actionKey: Self.readClipboardAlwaysTwoActionAfterKey,
                legacyBoolKey: Self.readClipboardAlwaysTwoTriggerAfterKey
            )
            refreshShortcutTriggerAccessibilityStatus()
        }
    }

    @Published var readClipboardAlwaysTwoSpeedMultiplier: Double {
        didSet {
            let clamped = SpeechRateMapper.clampMultiplier(readClipboardAlwaysTwoSpeedMultiplier)
            if clamped != readClipboardAlwaysTwoSpeedMultiplier {
                readClipboardAlwaysTwoSpeedMultiplier = clamped
                return
            }

            defaults.set(clamped, forKey: Self.readClipboardAlwaysTwoSpeedKey)
        }
    }

    @Published var readClipboardAlwaysThreeActionBefore: ExternalTriggerAction {
        didSet {
            persistExternalTriggerAction(
                readClipboardAlwaysThreeActionBefore,
                actionKey: Self.readClipboardAlwaysThreeActionBeforeKey,
                legacyBoolKey: Self.readClipboardAlwaysThreeTriggerBeforeKey
            )
            refreshShortcutTriggerAccessibilityStatus()
        }
    }

    @Published var readClipboardAlwaysThreeActionAfter: ExternalTriggerAction {
        didSet {
            persistExternalTriggerAction(
                readClipboardAlwaysThreeActionAfter,
                actionKey: Self.readClipboardAlwaysThreeActionAfterKey,
                legacyBoolKey: Self.readClipboardAlwaysThreeTriggerAfterKey
            )
            refreshShortcutTriggerAccessibilityStatus()
        }
    }

    @Published var readClipboardAlwaysThreeSpeedMultiplier: Double {
        didSet {
            let clamped = SpeechRateMapper.clampMultiplier(readClipboardAlwaysThreeSpeedMultiplier)
            if clamped != readClipboardAlwaysThreeSpeedMultiplier {
                readClipboardAlwaysThreeSpeedMultiplier = clamped
                return
            }

            defaults.set(clamped, forKey: Self.readClipboardAlwaysThreeSpeedKey)
        }
    }

    @Published var showPresenterOverlay: Bool {
        didSet {
            defaults.set(showPresenterOverlay, forKey: Self.presenterOverlayKey)
            refreshPresenterOverlayVisibility()
        }
    }

    @Published var hidePresenterOverlayFromCapture: Bool {
        didSet {
            defaults.set(hidePresenterOverlayFromCapture, forKey: Self.presenterOverlayCaptureKey)
            presenterOverlayController?.updateCaptureVisibility()
        }
    }

    @Published var hidePresenterOverlayWhileSpeaking: Bool {
        didSet {
            defaults.set(hidePresenterOverlayWhileSpeaking, forKey: Self.presenterOverlayHideWhileSpeakingKey)
            refreshPresenterOverlayVisibility()
        }
    }

    @Published var presenterOverlayOpacity: Double {
        didSet {
            let clamped = Self.clamp(presenterOverlayOpacity, min: Self.minPresenterOverlayOpacity, max: Self.maxPresenterOverlayOpacity)
            if clamped != presenterOverlayOpacity {
                presenterOverlayOpacity = clamped
                return
            }

            defaults.set(clamped, forKey: Self.presenterOverlayOpacityKey)
            presenterOverlayController?.updateLayout()
        }
    }

    @Published var presenterOverlayWidth: Double {
        didSet {
            let clamped = Self.clamp(presenterOverlayWidth, min: Self.minPresenterOverlayWidth, max: Self.maxPresenterOverlayWidth)
            if clamped != presenterOverlayWidth {
                presenterOverlayWidth = clamped
                return
            }

            defaults.set(clamped, forKey: Self.presenterOverlayWidthKey)
            presenterOverlayController?.updateLayout()
        }
    }

    @Published var presenterOverlayHeight: Double {
        didSet {
            let clamped = Self.clamp(presenterOverlayHeight, min: Self.minPresenterOverlayHeight, max: Self.maxPresenterOverlayHeight)
            if clamped != presenterOverlayHeight {
                presenterOverlayHeight = clamped
                return
            }

            defaults.set(clamped, forKey: Self.presenterOverlayHeightKey)
            presenterOverlayController?.updateLayout()
        }
    }

    @Published var presenterOverlayBottomOffset: Double {
        didSet {
            let clamped = Self.clamp(presenterOverlayBottomOffset, min: Self.minPresenterOverlayBottomOffset, max: Self.maxPresenterOverlayBottomOffset)
            if clamped != presenterOverlayBottomOffset {
                presenterOverlayBottomOffset = clamped
                return
            }

            defaults.set(clamped, forKey: Self.presenterOverlayBottomOffsetKey)
            presenterOverlayController?.updateLayout()
        }
    }

    @Published var presenterOverlayHorizontalOffset: Double {
        didSet {
            let clamped = Self.clamp(presenterOverlayHorizontalOffset, min: Self.minPresenterOverlayHorizontalOffset, max: Self.maxPresenterOverlayHorizontalOffset)
            if clamped != presenterOverlayHorizontalOffset {
                presenterOverlayHorizontalOffset = clamped
                return
            }

            defaults.set(clamped, forKey: Self.presenterOverlayHorizontalOffsetKey)
            presenterOverlayController?.updateLayout()
        }
    }

    @Published var presenterOverlayCurrentFontSize: Double {
        didSet {
            let clamped = Self.clamp(presenterOverlayCurrentFontSize, min: Self.minPresenterOverlayCurrentFontSize, max: Self.maxPresenterOverlayCurrentFontSize)
            if clamped != presenterOverlayCurrentFontSize {
                presenterOverlayCurrentFontSize = clamped
                return
            }

            defaults.set(clamped, forKey: Self.presenterOverlayCurrentFontSizeKey)
            presenterOverlayController?.updateLayout()
        }
    }

    @Published var presenterOverlaySideFontSize: Double {
        didSet {
            let clamped = Self.clamp(presenterOverlaySideFontSize, min: Self.minPresenterOverlaySideFontSize, max: Self.maxPresenterOverlaySideFontSize)
            if clamped != presenterOverlaySideFontSize {
                presenterOverlaySideFontSize = clamped
                return
            }

            defaults.set(clamped, forKey: Self.presenterOverlaySideFontSizeKey)
            presenterOverlayController?.updateLayout()
        }
    }

    @Published var presenterOverlayCurrentTextOpacity: Double {
        didSet {
            let clamped = Self.clamp(presenterOverlayCurrentTextOpacity, min: Self.minPresenterOverlayTextOpacity, max: Self.maxPresenterOverlayTextOpacity)
            if clamped != presenterOverlayCurrentTextOpacity {
                presenterOverlayCurrentTextOpacity = clamped
                return
            }

            defaults.set(clamped, forKey: Self.presenterOverlayCurrentTextOpacityKey)
        }
    }

    @Published var presenterOverlaySecondaryTextOpacity: Double {
        didSet {
            let clamped = Self.clamp(presenterOverlaySecondaryTextOpacity, min: Self.minPresenterOverlayTextOpacity, max: Self.maxPresenterOverlayTextOpacity)
            if clamped != presenterOverlaySecondaryTextOpacity {
                presenterOverlaySecondaryTextOpacity = clamped
                return
            }

            defaults.set(clamped, forKey: Self.presenterOverlaySecondaryTextOpacityKey)
        }
    }

    @Published var presenterOverlayCurrentTextColor: Color {
        didSet {
            if let hexString = presenterOverlayCurrentTextColor.hexString {
                defaults.set(hexString, forKey: Self.presenterOverlayCurrentTextColorKey)
            }
            presenterOverlayController?.updateLayout()
        }
    }

    @Published var presenterOverlaySecondaryTextColor: Color {
        didSet {
            if let hexString = presenterOverlaySecondaryTextColor.hexString {
                defaults.set(hexString, forKey: Self.presenterOverlaySecondaryTextColorKey)
            }
            presenterOverlayController?.updateLayout()
        }
    }

    @Published var scriptModeEnabled: Bool {
        didSet {
            defaults.set(scriptModeEnabled, forKey: Self.scriptModeKey)
            if scriptModeEnabled {
                readsTypedTextInsteadOfClipboard = true
                refreshScriptScenes()
            }
            refreshPresenterOverlayVisibility()
        }
    }

    @Published var readsTypedTextInsteadOfClipboard: Bool {
        didSet {
            defaults.set(readsTypedTextInsteadOfClipboard, forKey: Self.inputModeKey)
            if !readsTypedTextInsteadOfClipboard, scriptModeEnabled {
                scriptModeEnabled = false
            }
        }
    }

    @Published var speedMultiplier: Double {
        didSet {
            let clamped = SpeechRateMapper.clampMultiplier(speedMultiplier)
            if clamped != speedMultiplier {
                speedMultiplier = clamped
                return
            }

            defaults.set(clamped, forKey: Self.speedKey)
        }
    }

    @Published var selectedVoiceIdentifier: String? {
        didSet {
            defaults.set(selectedVoiceIdentifier, forKey: Self.voiceKey)
        }
    }

    var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().sorted {
            if $0.language == $1.language {
                return $0.name < $1.name
            }

            return $0.language < $1.language
        }
    }

    var selectedVoiceIdentifierForPicker: String {
        selectedVoiceIdentifier ?? ""
    }

    var readButtonTitle: String {
        if scriptModeEnabled {
            return "Play Scene"
        }

        return readsTypedTextInsteadOfClipboard ? "Read Text" : "Read Clipboard"
    }

    var inputModeStatus: String {
        if scriptModeEnabled {
            return "Shortcut plays the current script scene."
        }

        return readsTypedTextInsteadOfClipboard ? "Shortcut reads typed text." : "Shortcut reads clipboard."
    }

    var currentSceneText: String? {
        guard scriptScenes.indices.contains(currentSceneIndex) else {
            return nil
        }

        return scriptScenes[currentSceneIndex]
    }

    var currentNarrationScene: NarrationScene? {
        guard scriptInputFormat.usesStructuredScenes,
              let loadedChapter,
              loadedChapter.scenes.indices.contains(currentSceneIndex) else {
            return nil
        }
        return loadedChapter.scenes[currentSceneIndex]
    }

    var currentSceneTitle: String? {
        currentNarrationScene.map { "Scene \($0.sceneNumber)" }
    }

    var currentSceneDisplayTitle: String? {
        currentSceneTitle
    }

    var currentSceneVisualURL: URL? {
        nil
    }

    var currentSceneOnScreenSummary: String? {
        currentNarrationScene?.onScreen
    }

    var allSceneTexts: [String] {
        scriptScenes
    }

    var currentSceneIndexForEditor: Int {
        currentSceneIndex
    }

    var previousSceneText: String? {
        let previousIndex = currentSceneIndex - 1
        guard scriptScenes.indices.contains(previousIndex) else {
            return nil
        }

        return scriptScenes[previousIndex]
    }

    var previousSceneDisplayText: String? {
        guard scriptInputFormat.usesStructuredScenes else { return previousSceneText }
        let previousIndex = currentSceneIndex - 1
        guard let loadedChapter, loadedChapter.scenes.indices.contains(previousIndex) else { return nil }
        return "Scene \(loadedChapter.scenes[previousIndex].sceneNumber)"
    }

    var nextSceneText: String? {
        let nextIndex = currentSceneIndex + 1
        guard scriptScenes.indices.contains(nextIndex) else {
            return nil
        }

        return scriptScenes[nextIndex]
    }

    var nextSceneDisplayText: String? {
        guard scriptInputFormat.usesStructuredScenes else { return nextSceneText }
        let nextIndex = currentSceneIndex + 1
        guard let loadedChapter, loadedChapter.scenes.indices.contains(nextIndex) else { return nil }
        return "Scene \(loadedChapter.scenes[nextIndex].sceneNumber)"
    }

    var loadedChapterDescription: String? {
        if scriptInputFormat == .baserow {
            let title = baserowScripts.first(where: { $0.rowID == baserowSelectedScriptID })?.title
                ?? "Baserow Scenes"
            return baserowPartFilter.isEmpty ? title : "\(title) · \(baserowPartFilter)"
        }
        guard let loadedChapter else { return nil }
        return "Chapter \(loadedChapter.chapterNumber): \(loadedChapter.chapterTitle)"
    }

    var hasNotionConfiguration: Bool {
        !notionToken.isEmpty && !notionDataSourceID.isEmpty
    }

    var hasBaserowConfiguration: Bool {
        !baserowBaseURL.isEmpty && !baserowToken.isEmpty && !baserowTableID.isEmpty && !baserowScriptsTableID.isEmpty
    }

    var currentScenePart: String? {
        guard scriptInputFormat == .baserow, let scene = currentNarrationScene else { return nil }
        return baserowPartBySceneID[scene.id]
    }

    var hasConnectedSceneSource: Bool {
        switch scriptInputFormat {
        case .text: false
        case .json: isNotionConnected
        case .baserow: isBaserowConnected
        }
    }

    var scriptSceneProgress: String {
        guard !scriptScenes.isEmpty else {
            return "No scenes yet"
        }

        return "Scene \(currentSceneIndex + 1) of \(scriptScenes.count)"
    }

    var canGoToPreviousScene: Bool {
        currentSceneIndex > 0
    }

    var canGoToNextScene: Bool {
        currentSceneIndex + 1 < scriptScenes.count
    }

    var shouldShowPresenterOverlay: Bool {
        showPresenterOverlay
            && scriptModeEnabled
            && !(hidePresenterOverlayWhileSpeaking && speechState == .speaking)
    }

    var presenterOverlaySideColumnWidth: Double {
        min(280, max(150, presenterOverlayWidth * 0.22))
    }

    private static let speedKey = "clipboardReader.speedMultiplier"
    private static let voiceKey = "clipboardReader.voiceIdentifier"
    private static let inputModeKey = "clipboardReader.readsTypedTextInsteadOfClipboard"
    private static let scriptModeKey = "clipboardReader.scriptModeEnabled"
    private static let scriptInputFormatKey = "clipboardReader.scriptInputFormat"
    private static let lastChapterJSONPathKey = "clipboardReader.lastChapterJSONPath"
    private static let externalTTSStatePath = "/tmp/narration-pilot-tts-state.json"
    private static let notionDataSourceIDKey = "clipboardReader.notion.dataSourceID"
    private static let baserowBaseURLKey = "clipboardReader.baserow.baseURL"
    private static let baserowTableIDKey = "clipboardReader.baserow.tableID"
    private static let baserowScriptsTableIDKey = "clipboardReader.baserow.scriptsTableID"
    private static let baserowSelectedScriptIDKey = "clipboardReader.baserow.selectedScriptID"
    private static let baserowPartFilterKey = "clipboardReader.baserow.partFilter"
    private static let legacyRecordingShortcutTriggerKey = "clipboardReader.recordingShortcutTrigger.enabled"
    private static let recordingShortcutValueKey = "clipboardReader.recordingShortcutTrigger.shortcut"
    private static let accessibilityLaunchPromptAttemptedKey = "clipboardReader.accessibility.launchPromptAttempted"
    private static let recordingCueSoundsEnabledKey = "clipboardReader.recordingCueSounds.enabled"
    private static let recordingStartCueSoundKey = "clipboardReader.recordingCueSounds.startSound"
    private static let recordingStopCueSoundKey = "clipboardReader.recordingCueSounds.stopSound"
    private static let recordingFailureCueSoundKey = "clipboardReader.recordingCueSounds.failureSound"
    private static let recordingStartCueDelayKey = "clipboardReader.recordingCueSounds.startDelay"
    private static let recordingStopCueDelayKey = "clipboardReader.recordingCueSounds.stopDelay"
    private static let readShortcutOneTriggerBeforeKey = "clipboardReader.readShortcutOne.triggerBefore"
    private static let readShortcutOneTriggerAfterKey = "clipboardReader.readShortcutOne.triggerAfter"
    private static let readShortcutOneActionBeforeKey = "clipboardReader.readShortcutOne.actionBefore"
    private static let readShortcutOneActionAfterKey = "clipboardReader.readShortcutOne.actionAfter"
    private static let readShortcutOneDelayBeforeKey = "clipboardReader.readShortcutOne.delayBefore"
    private static let readShortcutOneDelayAfterKey = "clipboardReader.readShortcutOne.delayAfter"
    private static let readShortcutOneSpeedKey = "clipboardReader.readShortcutOne.speedMultiplier"
    private static let readShortcutOneWaitsForNeonSpotlightKey = "clipboardReader.readShortcutOne.waitsForNeonSpotlight"
    private static let readShortcutOneWaitsForUserInactivityKey = "clipboardReader.readShortcutOne.waitsForUserInactivity"
    private static let readShortcutTwoTriggerBeforeKey = "clipboardReader.readShortcutTwo.triggerBefore"
    private static let readShortcutTwoTriggerAfterKey = "clipboardReader.readShortcutTwo.triggerAfter"
    private static let readShortcutTwoActionBeforeKey = "clipboardReader.readShortcutTwo.actionBefore"
    private static let readShortcutTwoActionAfterKey = "clipboardReader.readShortcutTwo.actionAfter"
    private static let readShortcutTwoDelayBeforeKey = "clipboardReader.readShortcutTwo.delayBefore"
    private static let readShortcutTwoDelayAfterKey = "clipboardReader.readShortcutTwo.delayAfter"
    private static let readShortcutTwoSpeedKey = "clipboardReader.readShortcutTwo.speedMultiplier"
    private static let readShortcutTwoWaitsForNeonSpotlightKey = "clipboardReader.readShortcutTwo.waitsForNeonSpotlight"
    private static let readShortcutTwoWaitsForUserInactivityKey = "clipboardReader.readShortcutTwo.waitsForUserInactivity"
    private static let readClipboardAlwaysTriggerBeforeKey = "clipboardReader.readClipboardAlways.triggerBefore"
    private static let readClipboardAlwaysTriggerAfterKey = "clipboardReader.readClipboardAlways.triggerAfter"
    private static let readClipboardAlwaysActionBeforeKey = "clipboardReader.readClipboardAlways.actionBefore"
    private static let readClipboardAlwaysActionAfterKey = "clipboardReader.readClipboardAlways.actionAfter"
    private static let readClipboardAlwaysDelayBeforeKey = "clipboardReader.readClipboardAlways.delayBefore"
    private static let readClipboardAlwaysDelayAfterKey = "clipboardReader.readClipboardAlways.delayAfter"
    private static let readClipboardAlwaysSpeedKey = "clipboardReader.readClipboardAlways.speedMultiplier"
    private static let readClipboardAlwaysWaitsForNeonSpotlightKey = "clipboardReader.readClipboardAlways.waitsForNeonSpotlight"
    private static let readClipboardAlwaysWaitsForUserInactivityKey = "clipboardReader.readClipboardAlways.waitsForUserInactivity"
    private static let readClipboardAlwaysTwoTriggerBeforeKey = "clipboardReader.readClipboardAlwaysTwo.triggerBefore"
    private static let readClipboardAlwaysTwoTriggerAfterKey = "clipboardReader.readClipboardAlwaysTwo.triggerAfter"
    private static let readClipboardAlwaysTwoActionBeforeKey = "clipboardReader.readClipboardAlwaysTwo.actionBefore"
    private static let readClipboardAlwaysTwoActionAfterKey = "clipboardReader.readClipboardAlwaysTwo.actionAfter"
    private static let readClipboardAlwaysTwoDelayBeforeKey = "clipboardReader.readClipboardAlwaysTwo.delayBefore"
    private static let readClipboardAlwaysTwoDelayAfterKey = "clipboardReader.readClipboardAlwaysTwo.delayAfter"
    private static let readClipboardAlwaysTwoSpeedKey = "clipboardReader.readClipboardAlwaysTwo.speedMultiplier"
    private static let readClipboardAlwaysTwoWaitsForNeonSpotlightKey = "clipboardReader.readClipboardAlwaysTwo.waitsForNeonSpotlight"
    private static let readClipboardAlwaysTwoWaitsForUserInactivityKey = "clipboardReader.readClipboardAlwaysTwo.waitsForUserInactivity"
    private static let readClipboardAlwaysThreeTriggerBeforeKey = "clipboardReader.readClipboardAlwaysThree.triggerBefore"
    private static let readClipboardAlwaysThreeTriggerAfterKey = "clipboardReader.readClipboardAlwaysThree.triggerAfter"
    private static let readClipboardAlwaysThreeActionBeforeKey = "clipboardReader.readClipboardAlwaysThree.actionBefore"
    private static let readClipboardAlwaysThreeActionAfterKey = "clipboardReader.readClipboardAlwaysThree.actionAfter"
    private static let readClipboardAlwaysThreeDelayBeforeKey = "clipboardReader.readClipboardAlwaysThree.delayBefore"
    private static let readClipboardAlwaysThreeDelayAfterKey = "clipboardReader.readClipboardAlwaysThree.delayAfter"
    private static let readClipboardAlwaysThreeSpeedKey = "clipboardReader.readClipboardAlwaysThree.speedMultiplier"
    private static let readClipboardAlwaysThreeWaitsForNeonSpotlightKey = "clipboardReader.readClipboardAlwaysThree.waitsForNeonSpotlight"
    private static let readClipboardAlwaysThreeWaitsForUserInactivityKey = "clipboardReader.readClipboardAlwaysThree.waitsForUserInactivity"
    private static let userActivityIdlePeriodKey = "clipboardReader.userActivity.idlePeriod"
    private static let userActivityMaximumWaitKey = "clipboardReader.userActivity.maximumWait"
    private static let presenterOverlayKey = "clipboardReader.showPresenterOverlay"
    private static let presenterOverlayCaptureKey = "clipboardReader.hidePresenterOverlayFromCapture"
    private static let presenterOverlayHideWhileSpeakingKey = "clipboardReader.hidePresenterOverlayWhileSpeaking"
    private static let presenterOverlayOpacityKey = "clipboardReader.presenterOverlay.opacity"
    private static let presenterOverlayWidthKey = "clipboardReader.presenterOverlay.width"
    private static let presenterOverlayHeightKey = "clipboardReader.presenterOverlay.height"
    private static let presenterOverlayBottomOffsetKey = "clipboardReader.presenterOverlay.bottomOffset"
    private static let presenterOverlayHorizontalOffsetKey = "clipboardReader.presenterOverlay.horizontalOffset"
    private static let presenterOverlayCurrentFontSizeKey = "clipboardReader.presenterOverlay.currentFontSize"
    private static let presenterOverlaySideFontSizeKey = "clipboardReader.presenterOverlay.sideFontSize"
    private static let presenterOverlayCurrentTextOpacityKey = "clipboardReader.presenterOverlay.currentTextOpacity"
    private static let presenterOverlaySecondaryTextOpacityKey = "clipboardReader.presenterOverlay.secondaryTextOpacity"
    private static let presenterOverlayCurrentTextColorKey = "clipboardReader.presenterOverlay.currentTextColor"
    private static let presenterOverlaySecondaryTextColorKey = "clipboardReader.presenterOverlay.secondaryTextColor"

    static let defaultPresenterOverlayOpacity = 0.82
    static let defaultPresenterOverlayWidth = 980.0
    static let defaultPresenterOverlayHeight = 170.0
    static let defaultPresenterOverlayBottomOffset = 24.0
    static let defaultPresenterOverlayHorizontalOffset = 0.0
    static let defaultPresenterOverlayCurrentFontSize = 24.0
    static let defaultPresenterOverlaySideFontSize = 13.0
    static let defaultPresenterOverlayCurrentTextOpacity = 1.0
    static let defaultPresenterOverlaySecondaryTextOpacity = 0.68
    static let minPresenterOverlayOpacity = 0.2
    static let maxPresenterOverlayOpacity = 1.0
    static let minPresenterOverlayWidth = 520.0
    static let maxPresenterOverlayWidth = 1600.0
    static let minPresenterOverlayHeight = 120.0
    static let maxPresenterOverlayHeight = 420.0
    static let minPresenterOverlayBottomOffset = 0.0
    static let maxPresenterOverlayBottomOffset = 700.0
    static let minPresenterOverlayHorizontalOffset = -700.0
    static let maxPresenterOverlayHorizontalOffset = 700.0
    static let minPresenterOverlayCurrentFontSize = 16.0
    static let maxPresenterOverlayCurrentFontSize = 56.0
    static let minPresenterOverlaySideFontSize = 10.0
    static let maxPresenterOverlaySideFontSize = 32.0
    static let minPresenterOverlayTextOpacity = 0.1
    static let maxPresenterOverlayTextOpacity = 1.0
    static let minTriggerDelay = 0.0
    static let maxTriggerDelay = 10.0
    static let minRecordingStartCueDelay = 0.1
    static let maxRecordingStartCueDelay = 1.0
    static let minRecordingStopCueDelay = 0.0
    static let maxRecordingStopCueDelay = 1.0

    private let defaults: UserDefaults
    private let clipboardService = ClipboardService()
    private let shortcutTriggerService = ShortcutTriggerService()
    private let focuSeeAccessibilityService = FocuSeeAccessibilityService()
    private let neonSpotlightStatusService = NeonSpotlightStatusService()
    private let userActivityIdleService = UserActivityIdleService()
    private let chapterFileWatcher = ChapterFileWatcher()
    private let notionSceneService = NotionSceneService()
    private let baserowSceneService = BaserowSceneService()
    private let ttsManager = TTSManager()
    private var cancellables = Set<AnyCancellable>()
    private var presenterOverlayController: PresenterOverlayController?
    private var sceneEditorController: SceneEditorController?
    @Published private var currentSceneIndex = 0
    @Published private var scriptScenes: [String] = []
    private var manualSceneOverride: [String]?
    private var manualSceneOverrideSource: String?
    private var shouldAdvanceScriptSceneAfterSpeech = false
    private var externalTriggerActionAfterSpeech: ExternalTriggerAction = .none
    private var externalTriggerDelayAfterSpeech = 0.0
    private var waitsForNeonSpotlightAfterSpeech = false
    private var waitsForUserInactivityAfterSpeech = false
    private var activeReadSequenceID: UUID?
    private var pendingReadTask: Task<Void, Never>?
    private var pendingChapterReloadURL: URL?
    private var notionPageIDsBySceneID: [String: String] = [:]
    private var notionLastEditedBySceneID: [String: Date] = [:]
    private var notionRevision = ""
    private var baserowRowIDsBySceneID: [String: Int] = [:]
    private var baserowOriginalSceneNumbersBySceneID: [String: Int] = [:]
    private var baserowPartBySceneID: [String: String] = [:]
    private var baserowScriptIDsBySceneID: [String: Int] = [:]
    private var baserowLastEditedBySceneID: [String: Date] = [:]
    private var baserowRevision = ""
    private var baserowSyncRequested = false
    private var baserowSyncWaiters: [CheckedContinuation<Void, Never>] = []
    private struct BaserowUndoEntry {
        let actionName: String
        let scriptID: Int
        let before: [BaserowSceneRecord]
        let expectedAfterSignature: String
        let preferredSceneNumber: Int
    }
    private var baserowUndoEntry: BaserowUndoEntry?
    private var sceneManagerNarrationQueue: [(sceneID: String, narration: String)] = []

    /// Notion "last edited" timestamp for a scene ID, when the chapter came from Notion.
    func notionLastEdited(forSceneID sceneID: String) -> Date? {
        notionLastEditedBySceneID[sceneID]
    }

    func sceneLastEdited(forSceneID sceneID: String) -> Date? {
        switch scriptInputFormat {
        case .text: nil
        case .json: notionLastEditedBySceneID[sceneID]
        case .baserow: baserowLastEditedBySceneID[sceneID]
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedSpeed = defaults.object(forKey: Self.speedKey) as? Double
        let legacyTriggerBefore = defaults.bool(forKey: Self.legacyRecordingShortcutTriggerKey)
        let initialSpeedMultiplier = SpeechRateMapper.clampMultiplier(storedSpeed ?? SpeechRateMapper.defaultMultiplier)
        self.speedMultiplier = initialSpeedMultiplier
        self.selectedVoiceIdentifier = defaults.string(forKey: Self.voiceKey)
        self.readsTypedTextInsteadOfClipboard = defaults.bool(forKey: Self.inputModeKey)
        self.scriptModeEnabled = defaults.bool(forKey: Self.scriptModeKey)
        self.scriptInputFormat = ScriptInputFormat(
            rawValue: defaults.string(forKey: Self.scriptInputFormatKey) ?? "text"
        ) ?? .text
        self.loadedChapter = nil
        self.loadedChapterURL = nil
        self.notionToken = NotionTokenStore.load()
        self.notionDataSourceID = defaults.string(forKey: Self.notionDataSourceIDKey) ?? "81db58ed-5ad8-45b5-bac5-893d68d697eb"
        self.baserowBaseURL = defaults.string(forKey: Self.baserowBaseURLKey) ?? "http://host.docker.internal:85"
        self.baserowToken = BaserowTokenStore.load()
        self.baserowTableID = defaults.string(forKey: Self.baserowTableIDKey) ?? "739"
        self.baserowScriptsTableID = defaults.string(forKey: Self.baserowScriptsTableIDKey) ?? "740"
        self.baserowSelectedScriptID = defaults.integer(forKey: Self.baserowSelectedScriptIDKey)
        self.baserowPartFilter = defaults.string(forKey: Self.baserowPartFilterKey) ?? ""
        self.recordingCueSoundsEnabled = defaults.bool(forKey: Self.recordingCueSoundsEnabledKey)
        self.recordingStartCueSound = RecordingCueSound(
            rawValue: defaults.string(forKey: Self.recordingStartCueSoundKey) ?? RecordingCueSound.pop.rawValue
        ) ?? .pop
        self.recordingStopCueSound = RecordingCueSound(
            rawValue: defaults.string(forKey: Self.recordingStopCueSoundKey) ?? RecordingCueSound.glass.rawValue
        ) ?? .glass
        self.recordingFailureCueSound = RecordingFailureCueSound(
            rawValue: defaults.string(forKey: Self.recordingFailureCueSoundKey) ?? RecordingFailureCueSound.sameAsStop.rawValue
        ) ?? .sameAsStop
        self.recordingStartCueDelay = Self.clampRecordingStartCueDelay(Self.storedDouble(
            in: defaults,
            forKey: Self.recordingStartCueDelayKey,
            defaultValue: 0.3
        ))
        self.recordingStopCueDelay = Self.clampRecordingStopCueDelay(Self.storedDouble(
            in: defaults,
            forKey: Self.recordingStopCueDelayKey,
            defaultValue: 0.1
        ))
        self.readShortcutOneActionBefore = Self.storedExternalTriggerAction(
            in: defaults,
            actionKey: Self.readShortcutOneActionBeforeKey,
            legacyBoolKey: Self.readShortcutOneTriggerBeforeKey,
            legacyDefaultValue: legacyTriggerBefore
        )
        self.readShortcutOneActionAfter = Self.storedExternalTriggerAction(
            in: defaults,
            actionKey: Self.readShortcutOneActionAfterKey,
            legacyBoolKey: Self.readShortcutOneTriggerAfterKey
        )
        self.readShortcutOneDelayBefore = Self.storedTriggerDelay(in: defaults, forKey: Self.readShortcutOneDelayBeforeKey)
        self.readShortcutOneDelayAfter = Self.storedTriggerDelay(in: defaults, forKey: Self.readShortcutOneDelayAfterKey)
        self.readShortcutOneSpeedMultiplier = SpeechRateMapper.clampMultiplier(Self.storedDouble(
            in: defaults,
            forKey: Self.readShortcutOneSpeedKey,
            defaultValue: initialSpeedMultiplier
        ))
        self.readShortcutOneWaitsForNeonSpotlight = defaults.bool(forKey: Self.readShortcutOneWaitsForNeonSpotlightKey)
        self.readShortcutOneWaitsForUserInactivity = defaults.bool(forKey: Self.readShortcutOneWaitsForUserInactivityKey)
        self.readShortcutTwoActionBefore = Self.storedExternalTriggerAction(
            in: defaults,
            actionKey: Self.readShortcutTwoActionBeforeKey,
            legacyBoolKey: Self.readShortcutTwoTriggerBeforeKey
        )
        self.readShortcutTwoActionAfter = Self.storedExternalTriggerAction(
            in: defaults,
            actionKey: Self.readShortcutTwoActionAfterKey,
            legacyBoolKey: Self.readShortcutTwoTriggerAfterKey
        )
        self.readShortcutTwoDelayBefore = Self.storedTriggerDelay(in: defaults, forKey: Self.readShortcutTwoDelayBeforeKey)
        self.readShortcutTwoDelayAfter = Self.storedTriggerDelay(in: defaults, forKey: Self.readShortcutTwoDelayAfterKey)
        self.readShortcutTwoSpeedMultiplier = SpeechRateMapper.clampMultiplier(Self.storedDouble(
            in: defaults,
            forKey: Self.readShortcutTwoSpeedKey,
            defaultValue: initialSpeedMultiplier
        ))
        self.readShortcutTwoWaitsForNeonSpotlight = defaults.bool(forKey: Self.readShortcutTwoWaitsForNeonSpotlightKey)
        self.readShortcutTwoWaitsForUserInactivity = defaults.bool(forKey: Self.readShortcutTwoWaitsForUserInactivityKey)
        self.readClipboardAlwaysActionBefore = Self.storedExternalTriggerAction(
            in: defaults,
            actionKey: Self.readClipboardAlwaysActionBeforeKey,
            legacyBoolKey: Self.readClipboardAlwaysTriggerBeforeKey
        )
        self.readClipboardAlwaysActionAfter = Self.storedExternalTriggerAction(
            in: defaults,
            actionKey: Self.readClipboardAlwaysActionAfterKey,
            legacyBoolKey: Self.readClipboardAlwaysTriggerAfterKey
        )
        self.readClipboardAlwaysDelayBefore = Self.storedTriggerDelay(in: defaults, forKey: Self.readClipboardAlwaysDelayBeforeKey)
        self.readClipboardAlwaysDelayAfter = Self.storedTriggerDelay(in: defaults, forKey: Self.readClipboardAlwaysDelayAfterKey)
        self.readClipboardAlwaysSpeedMultiplier = SpeechRateMapper.clampMultiplier(Self.storedDouble(
            in: defaults,
            forKey: Self.readClipboardAlwaysSpeedKey,
            defaultValue: initialSpeedMultiplier
        ))
        self.readClipboardAlwaysWaitsForNeonSpotlight = defaults.bool(forKey: Self.readClipboardAlwaysWaitsForNeonSpotlightKey)
        self.readClipboardAlwaysWaitsForUserInactivity = defaults.bool(forKey: Self.readClipboardAlwaysWaitsForUserInactivityKey)
        self.readClipboardAlwaysTwoActionBefore = Self.storedExternalTriggerAction(
            in: defaults,
            actionKey: Self.readClipboardAlwaysTwoActionBeforeKey,
            legacyBoolKey: Self.readClipboardAlwaysTwoTriggerBeforeKey
        )
        self.readClipboardAlwaysTwoActionAfter = Self.storedExternalTriggerAction(
            in: defaults,
            actionKey: Self.readClipboardAlwaysTwoActionAfterKey,
            legacyBoolKey: Self.readClipboardAlwaysTwoTriggerAfterKey
        )
        self.readClipboardAlwaysTwoDelayBefore = Self.storedTriggerDelay(in: defaults, forKey: Self.readClipboardAlwaysTwoDelayBeforeKey)
        self.readClipboardAlwaysTwoDelayAfter = Self.storedTriggerDelay(in: defaults, forKey: Self.readClipboardAlwaysTwoDelayAfterKey)
        self.readClipboardAlwaysTwoSpeedMultiplier = SpeechRateMapper.clampMultiplier(Self.storedDouble(
            in: defaults,
            forKey: Self.readClipboardAlwaysTwoSpeedKey,
            defaultValue: initialSpeedMultiplier
        ))
        self.readClipboardAlwaysTwoWaitsForNeonSpotlight = defaults.bool(forKey: Self.readClipboardAlwaysTwoWaitsForNeonSpotlightKey)
        self.readClipboardAlwaysTwoWaitsForUserInactivity = defaults.bool(forKey: Self.readClipboardAlwaysTwoWaitsForUserInactivityKey)
        self.readClipboardAlwaysThreeActionBefore = Self.storedExternalTriggerAction(
            in: defaults,
            actionKey: Self.readClipboardAlwaysThreeActionBeforeKey,
            legacyBoolKey: Self.readClipboardAlwaysThreeTriggerBeforeKey
        )
        self.readClipboardAlwaysThreeActionAfter = Self.storedExternalTriggerAction(
            in: defaults,
            actionKey: Self.readClipboardAlwaysThreeActionAfterKey,
            legacyBoolKey: Self.readClipboardAlwaysThreeTriggerAfterKey
        )
        self.readClipboardAlwaysThreeDelayBefore = Self.storedTriggerDelay(in: defaults, forKey: Self.readClipboardAlwaysThreeDelayBeforeKey)
        self.readClipboardAlwaysThreeDelayAfter = Self.storedTriggerDelay(in: defaults, forKey: Self.readClipboardAlwaysThreeDelayAfterKey)
        self.readClipboardAlwaysThreeSpeedMultiplier = SpeechRateMapper.clampMultiplier(Self.storedDouble(
            in: defaults,
            forKey: Self.readClipboardAlwaysThreeSpeedKey,
            defaultValue: initialSpeedMultiplier
        ))
        self.readClipboardAlwaysThreeWaitsForNeonSpotlight = defaults.bool(forKey: Self.readClipboardAlwaysThreeWaitsForNeonSpotlightKey)
        self.readClipboardAlwaysThreeWaitsForUserInactivity = defaults.bool(forKey: Self.readClipboardAlwaysThreeWaitsForUserInactivityKey)
        self.userActivityIdlePeriod = UserActivityIdlePolicy.clampedIdlePeriod(Self.storedDouble(
            in: defaults,
            forKey: Self.userActivityIdlePeriodKey,
            defaultValue: UserActivityIdlePolicy.defaultIdlePeriod
        ))
        self.userActivityMaximumWait = UserActivityIdlePolicy.clampedMaximumWait(Self.storedDouble(
            in: defaults,
            forKey: Self.userActivityMaximumWaitKey,
            defaultValue: UserActivityIdlePolicy.defaultMaximumWait
        ))
        self.recordingTriggerShortcut = Self.storedRecordingTriggerShortcut(in: defaults)
        self.isShortcutTriggerAccessibilityTrusted = ShortcutTriggerService.isAccessibilityTrusted
        self.showPresenterOverlay = defaults.bool(forKey: Self.presenterOverlayKey)
        self.hidePresenterOverlayFromCapture = (defaults.object(forKey: Self.presenterOverlayCaptureKey) as? Bool) ?? true
        self.hidePresenterOverlayWhileSpeaking = defaults.bool(forKey: Self.presenterOverlayHideWhileSpeakingKey)
        self.presenterOverlayOpacity = Self.storedDouble(
            in: defaults,
            forKey: Self.presenterOverlayOpacityKey,
            defaultValue: Self.defaultPresenterOverlayOpacity
        )
        self.presenterOverlayWidth = Self.storedDouble(
            in: defaults,
            forKey: Self.presenterOverlayWidthKey,
            defaultValue: Self.defaultPresenterOverlayWidth
        )
        self.presenterOverlayHeight = Self.storedDouble(
            in: defaults,
            forKey: Self.presenterOverlayHeightKey,
            defaultValue: Self.defaultPresenterOverlayHeight
        )
        self.presenterOverlayBottomOffset = Self.storedDouble(
            in: defaults,
            forKey: Self.presenterOverlayBottomOffsetKey,
            defaultValue: Self.defaultPresenterOverlayBottomOffset
        )
        self.presenterOverlayHorizontalOffset = Self.storedDouble(
            in: defaults,
            forKey: Self.presenterOverlayHorizontalOffsetKey,
            defaultValue: Self.defaultPresenterOverlayHorizontalOffset
        )
        self.presenterOverlayCurrentFontSize = Self.storedDouble(
            in: defaults,
            forKey: Self.presenterOverlayCurrentFontSizeKey,
            defaultValue: Self.defaultPresenterOverlayCurrentFontSize
        )
        self.presenterOverlaySideFontSize = Self.storedDouble(
            in: defaults,
            forKey: Self.presenterOverlaySideFontSizeKey,
            defaultValue: Self.defaultPresenterOverlaySideFontSize
        )
        self.presenterOverlayCurrentTextOpacity = Self.storedDouble(
            in: defaults,
            forKey: Self.presenterOverlayCurrentTextOpacityKey,
            defaultValue: Self.defaultPresenterOverlayCurrentTextOpacity
        )
        self.presenterOverlaySecondaryTextOpacity = Self.storedDouble(
            in: defaults,
            forKey: Self.presenterOverlaySecondaryTextOpacityKey,
            defaultValue: Self.defaultPresenterOverlaySecondaryTextOpacity
        )
        self.presenterOverlayCurrentTextColor = Color(
            hexString: defaults.string(forKey: Self.presenterOverlayCurrentTextColorKey) ?? "#FFFFFFFF",
            fallback: .white
        )
        self.presenterOverlaySecondaryTextColor = Color(
            hexString: defaults.string(forKey: Self.presenterOverlaySecondaryTextColorKey) ?? "#D8DEE9FF",
            fallback: Color(red: 0.85, green: 0.87, blue: 0.91)
        )

        bindSpeechState()
        registerShortcutHandlers()
        presenterOverlayController = PresenterOverlayController(appModel: self)
        sceneEditorController = SceneEditorController(appModel: self)
        persistExternalSpeechState(.idle)
        DispatchQueue.main.async { [weak self] in
            self?.refreshPresenterOverlayVisibility()
        }
    }

    func readNow(
        actionBefore: ExternalTriggerAction = .none,
        actionAfter: ExternalTriggerAction = .none,
        delayBefore: Double = 0,
        delayAfter: Double = 0,
        waitsForNeonSpotlight: Bool = false,
        waitsForUserInactivity: Bool = false,
        speedMultiplier: Double? = nil
    ) {
        let resolvedSpeedMultiplier = speedMultiplier ?? self.speedMultiplier

        if scriptModeEnabled {
            readCurrentScriptSceneNow(
                actionBefore: actionBefore,
                actionAfter: actionAfter,
                delayBefore: delayBefore,
                delayAfter: delayAfter,
                waitsForNeonSpotlight: waitsForNeonSpotlight,
                waitsForUserInactivity: waitsForUserInactivity,
                speedMultiplier: resolvedSpeedMultiplier
            )
            return
        }

        if readsTypedTextInsteadOfClipboard {
            readTypedTextNow(
                actionBefore: actionBefore,
                actionAfter: actionAfter,
                delayBefore: delayBefore,
                delayAfter: delayAfter,
                waitsForNeonSpotlight: waitsForNeonSpotlight,
                waitsForUserInactivity: waitsForUserInactivity,
                speedMultiplier: resolvedSpeedMultiplier
            )
        } else {
            readClipboardNow(
                actionBefore: actionBefore,
                actionAfter: actionAfter,
                delayBefore: delayBefore,
                delayAfter: delayAfter,
                waitsForNeonSpotlight: waitsForNeonSpotlight,
                waitsForUserInactivity: waitsForUserInactivity,
                speedMultiplier: resolvedSpeedMultiplier
            )
        }
    }

    func speakExternalNarration(_ text: String) {
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedText.isEmpty else {
            statusMessage = "Narration is empty."
            return
        }

        cancelPendingReadSequence()
        shouldAdvanceScriptSceneAfterSpeech = false
        statusMessage = "Reading narration from Ultimate Video Editor…"
        ttsManager.speak(
            text: cleanedText,
            speedMultiplier: speedMultiplier,
            voiceIdentifier: selectedVoiceIdentifier
        )
    }

    func pauseExternalNarration() {
        guard speechState == .speaking else { return }
        ttsManager.togglePauseResume()
    }

    func resumeExternalNarration() {
        guard speechState == .paused else { return }
        ttsManager.togglePauseResume()
    }

    func stopExternalNarration() {
        stopReading()
    }

    func handleExternalTTSURL(_ requestURL: URL) {
        guard requestURL.scheme == "narrationpilot",
              let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false) else {
            return
        }

        switch requestURL.host {
        case "speak":
            guard let text = components.queryItems?.first(where: { $0.name == "text" })?.value else { return }
            speakExternalNarration(text)
        case "pause":
            pauseExternalNarration()
        case "resume":
            resumeExternalNarration()
        case "stop":
            stopExternalNarration()
        default:
            return
        }
    }

    func readClipboardAlways(
        actionBefore: ExternalTriggerAction = .none,
        actionAfter: ExternalTriggerAction = .none,
        delayBefore: Double = 0,
        delayAfter: Double = 0,
        waitsForNeonSpotlight: Bool = false,
        waitsForUserInactivity: Bool = false,
        speedMultiplier: Double? = nil
    ) {
        readClipboardNow(
            actionBefore: actionBefore,
            actionAfter: actionAfter,
            delayBefore: delayBefore,
            delayAfter: delayAfter,
            waitsForNeonSpotlight: waitsForNeonSpotlight,
            waitsForUserInactivity: waitsForUserInactivity,
            speedMultiplier: speedMultiplier ?? self.speedMultiplier
        )
    }

    func clearTypedText() {
        manualSceneOverride = nil
        manualSceneOverrideSource = nil
        typedText = ""
        refreshScriptScenes()
    }

    func restoreNotionIfAvailable() {
        guard !notionToken.isEmpty, !notionDataSourceID.isEmpty else {
            restoreNotionCache()
            return
        }
        connectNotion()
    }

    func connectNotion() {
        let token = notionToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let dataSourceID = notionDataSourceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !dataSourceID.isEmpty else {
            statusMessage = "Enter a Notion token and data source ID."
            return
        }
        notionToken = token
        notionDataSourceID = dataSourceID
        NotionTokenStore.save(token)
        defaults.set(dataSourceID, forKey: Self.notionDataSourceIDKey)
        Task { await syncNotionScenes(force: true) }
    }

    func syncNotionNow() {
        Task { await syncNotionScenes(force: true) }
    }

    func disconnectNotion() {
        isNotionConnected = false
        notionPageIDsBySceneID = [:]
        notionRevision = ""
        NotionTokenStore.save("")
        notionToken = ""
        statusMessage = "Notion disconnected."
    }

    private func syncNotionScenes(force: Bool) async {
        guard !notionToken.isEmpty, !notionDataSourceID.isEmpty, !isNotionSyncing else { return }
        isNotionSyncing = true
        defer { isNotionSyncing = false }
        do {
            let records = try await notionSceneService.fetchScenes(token: notionToken, dataSourceID: notionDataSourceID)
            guard !records.isEmpty else { throw NotionSceneError.invalidScenes("The Notion scene database is empty.") }
            let revision = records.map { "\($0.pageID):\($0.lastEditedTime)" }.joined(separator: "|")
            if !force, revision == notionRevision { return }
            let chapter = NarrationChapter(
                schemaVersion: NarrationChapterLoader.supportedSchemaVersion,
                chapterNumber: 1,
                chapterTitle: "Notion Scenes",
                scenes: records.map(\.scene)
            )
            try NarrationChapterLoader.validate(chapter)
            let previousSceneID = currentNarrationScene?.id
            loadedChapter = chapter
            loadedChapterURL = nil
            notionPageIDsBySceneID = Dictionary(uniqueKeysWithValues: records.map { ($0.scene.id, $0.pageID) })
            notionLastEditedBySceneID = Dictionary(uniqueKeysWithValues: records.compactMap { record in
                guard let date = NotionSceneService.dateFormatter.date(from: record.lastEditedTime) else { return nil }
                return (record.scene.id, date)
            })
            notionRevision = revision
            isNotionConnected = true
            scriptInputFormat = .json
            scriptModeEnabled = true
            readsTypedTextInsteadOfClipboard = true
            refreshScriptScenes()
            if let previousSceneID, let index = chapter.scenes.firstIndex(where: { $0.id == previousSceneID }) {
                currentSceneIndex = index
            }
            saveNotionCache(chapter)
            statusMessage = "Notion synced. \(scriptSceneProgress)"
            presenterOverlayController?.updateLayout()
        } catch {
            if !isNotionConnected { restoreNotionCache() }
            statusMessage = "Notion sync failed: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    private func saveNotionCache(_ chapter: NarrationChapter) {
        guard let data = try? JSONEncoder.narrationPilot.encode(chapter) else { return }
        try? FileManager.default.createDirectory(at: notionCacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: notionCacheURL, options: .atomic)
    }

    private func restoreNotionCache() {
        guard let chapter = try? NarrationChapterLoader.load(from: notionCacheURL) else { return }
        loadedChapter = chapter
        loadedChapterURL = nil
        scriptInputFormat = .json
        scriptModeEnabled = true
        refreshScriptScenes()
        statusMessage = "Using cached Notion scenes offline."
    }

    private var notionCacheURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Narration Pilot", isDirectory: true).appendingPathComponent("notion-scenes-cache.json")
    }

    func restoreBaserowIfAvailable() {
        guard hasBaserowConfiguration else {
            restoreBaserowCache()
            return
        }
        connectBaserow()
    }

    func connectBaserow() {
        let baseURL = baserowBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = baserowToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let tableID = baserowTableID.trimmingCharacters(in: .whitespacesAndNewlines)
        let scriptsTableID = baserowScriptsTableID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseURL.isEmpty, !token.isEmpty, !tableID.isEmpty, !scriptsTableID.isEmpty else {
            statusMessage = "Enter a Baserow URL, token, scenes table ID, and scripts table ID."
            return
        }
        baserowBaseURL = baseURL
        baserowToken = token
        baserowTableID = tableID
        baserowScriptsTableID = scriptsTableID
        BaserowTokenStore.save(token)
        defaults.set(baseURL, forKey: Self.baserowBaseURLKey)
        defaults.set(tableID, forKey: Self.baserowTableIDKey)
        defaults.set(scriptsTableID, forKey: Self.baserowScriptsTableIDKey)
        Task { await syncBaserowScenes(force: true) }
    }

    func syncBaserowNow() {
        Task { await syncBaserowScenes(force: true) }
    }

    func disconnectBaserow() {
        clearBaserowUndo()
        isBaserowConnected = false
        baserowScripts = []
        baserowPartOptions = []
        baserowRowIDsBySceneID = [:]
        baserowOriginalSceneNumbersBySceneID = [:]
        baserowPartBySceneID = [:]
        baserowScriptIDsBySceneID = [:]
        baserowLastEditedBySceneID = [:]
        baserowRevision = ""
        BaserowTokenStore.save("")
        baserowToken = ""
        statusMessage = "Baserow disconnected."
    }

    func selectBaserowScript(_ scriptID: Int) {
        guard baserowSelectedScriptID != scriptID else { return }
        stopSceneManagerNarrationQueue()
        baserowSelectedScriptID = scriptID
        currentSceneIndex = 0
        Task { await syncBaserowScenes(force: true) }
    }

    func selectBaserowPart(_ part: String) {
        guard baserowPartFilter != part else { return }
        stopSceneManagerNarrationQueue()
        baserowPartFilter = part
        currentSceneIndex = 0
        Task { await syncBaserowScenes(force: true) }
    }

    func deleteBaserowScene(sceneID: String) async {
        guard scriptInputFormat == .baserow,
              let rowID = baserowRowIDsBySceneID[sceneID],
              let originalSceneNumber = baserowOriginalSceneNumbersBySceneID[sceneID],
              let scriptID = baserowScriptIDsBySceneID[sceneID] else {
            statusMessage = "The selected Baserow scene could not be identified."
            return
        }

        if isBaserowSyncing {
            await syncBaserowScenes(force: true)
        }

        do {
            let records = try await baserowSceneService.fetchScenes(
                baseURL: baserowBaseURL,
                token: baserowToken,
                tableID: baserowTableID
            )
            guard records.contains(where: { $0.rowID == rowID && $0.scriptIDs.contains(scriptID) }) else {
                statusMessage = "That Baserow scene no longer exists. Refreshing scenes…"
                await syncBaserowScenes(force: true)
                return
            }
            let undoSnapshot = records.filter { $0.scriptIDs.contains(scriptID) }

            statusMessage = "Deleting Scene \(originalSceneNumber) from Baserow…"
            try await baserowSceneService.deleteScene(
                rowID: rowID,
                baseURL: baserowBaseURL,
                token: baserowToken,
                tableID: baserowTableID
            )

            let laterRecords = records
                .filter { $0.rowID != rowID && $0.scriptIDs.contains(scriptID) && $0.originalSceneNumber > originalSceneNumber }
                .sorted { $0.originalSceneNumber < $1.originalSceneNumber }
            for record in laterRecords {
                try await baserowSceneService.updateSceneNumber(
                    rowID: record.rowID,
                    sceneNumber: record.originalSceneNumber - 1,
                    baseURL: baserowBaseURL,
                    token: baserowToken,
                    tableID: baserowTableID
                )
            }

            baserowRevision = ""
            currentSceneIndex = min(currentSceneIndex, max((loadedChapter?.scenes.count ?? 1) - 2, 0))
            await syncBaserowScenes(force: true)
            await registerBaserowUndo(
                actionName: "Delete Scene", scriptID: scriptID,
                before: undoSnapshot, preferredSceneNumber: originalSceneNumber
            )
            statusMessage = "Scene deleted from Baserow. \(scriptSceneProgress)"
        } catch {
            baserowRevision = ""
            await syncBaserowScenes(force: true)
            statusMessage = "Baserow delete failed: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    func addBaserowScene(afterSceneID sceneID: String) async {
        guard scriptInputFormat == .baserow,
              let originalSceneNumber = baserowOriginalSceneNumbersBySceneID[sceneID],
              let scriptID = baserowScriptIDsBySceneID[sceneID] else {
            statusMessage = "The selected Baserow scene could not be identified."
            return
        }
        let part = baserowPartBySceneID[sceneID]

        if isBaserowSyncing {
            await syncBaserowScenes(force: true)
        }

        var renumberedRecords: [BaserowSceneRecord] = []
        var createdRowID: Int?
        do {
            let records = try await baserowSceneService.fetchScenes(
                baseURL: baserowBaseURL,
                token: baserowToken,
                tableID: baserowTableID
            )
            guard records.contains(where: { $0.scene.id == sceneID && $0.scriptIDs.contains(scriptID) }) else {
                statusMessage = "That Baserow scene no longer exists. Refreshing scenes…"
                await syncBaserowScenes(force: true)
                return
            }
            let undoSnapshot = records.filter { $0.scriptIDs.contains(scriptID) }

            statusMessage = "Adding a scene after Scene \(originalSceneNumber)…"
            let laterRecords = records
                .filter { $0.scriptIDs.contains(scriptID) && $0.originalSceneNumber > originalSceneNumber }
                .sorted { $0.originalSceneNumber > $1.originalSceneNumber }
            for record in laterRecords {
                try await baserowSceneService.updateSceneNumber(
                    rowID: record.rowID,
                    sceneNumber: record.originalSceneNumber + 1,
                    baseURL: baserowBaseURL,
                    token: baserowToken,
                    tableID: baserowTableID
                )
                renumberedRecords.append(record)
            }

            createdRowID = try await baserowSceneService.createEmptyScene(
                sceneNumber: originalSceneNumber + 1,
                part: part,
                scriptID: scriptID,
                baseURL: baserowBaseURL,
                token: baserowToken,
                tableID: baserowTableID
            )

            baserowRevision = ""
            await syncBaserowScenes(force: true)
            if let createdRowID,
               let index = loadedChapter?.scenes.firstIndex(where: { $0.id == "baserow-row-\(createdRowID)" }) {
                currentSceneIndex = index
            }
            await registerBaserowUndo(
                actionName: "Add Scene", scriptID: scriptID,
                before: undoSnapshot, preferredSceneNumber: originalSceneNumber
            )
            statusMessage = "Empty scene added. \(scriptSceneProgress)"
        } catch {
            if createdRowID == nil {
                for record in renumberedRecords.reversed() {
                    try? await baserowSceneService.updateSceneNumber(
                        rowID: record.rowID,
                        sceneNumber: record.originalSceneNumber,
                        baseURL: baserowBaseURL,
                        token: baserowToken,
                        tableID: baserowTableID
                    )
                }
            }
            baserowRevision = ""
            await syncBaserowScenes(force: true)
            statusMessage = "Baserow add failed: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    func combineBaserowSceneWithNext(sceneID: String) async {
        guard scriptInputFormat == .baserow,
              let rowID = baserowRowIDsBySceneID[sceneID],
              let scriptID = baserowScriptIDsBySceneID[sceneID] else {
            statusMessage = "The selected Baserow scene could not be identified."
            return
        }
        if isBaserowSyncing { await syncBaserowScenes(force: true) }

        var originalRecord: BaserowSceneRecord?
        var nextRecord: BaserowSceneRecord?
        var combinedWasSaved = false
        var nextWasDeleted = false
        var renumberedRecords: [BaserowSceneRecord] = []
        do {
            let records = try await baserowSceneService.fetchScenes(
                baseURL: baserowBaseURL, token: baserowToken, tableID: baserowTableID
            )
            let scriptRecords = records
                .filter { $0.scriptIDs.contains(scriptID) }
                .sorted { $0.originalSceneNumber < $1.originalSceneNumber }
            let undoSnapshot = scriptRecords
            guard let currentIndex = scriptRecords.firstIndex(where: { $0.rowID == rowID }),
                  scriptRecords.indices.contains(currentIndex + 1) else {
                statusMessage = "There is no next scene to combine."
                return
            }
            let current = scriptRecords[currentIndex]
            let next = scriptRecords[currentIndex + 1]
            originalRecord = current
            nextRecord = next
            guard Set(current.scriptIDs) == Set(next.scriptIDs), current.part == next.part else {
                statusMessage = "Scenes can only be combined when their Script and Part match."
                return
            }
            guard next.scene.code == nil else {
                statusMessage = "The next scene contains code. Move or remove its code before combining."
                return
            }

            let combined = NarrationScene(
                id: current.scene.id,
                sceneNumber: current.scene.sceneNumber,
                narration: Self.joinSceneText(current.scene.narration, next.scene.narration, separator: " "),
                onScreen: Self.joinSceneText(current.scene.onScreen, next.scene.onScreen, separator: "\n"),
                code: current.scene.code,
                annotation: Self.joinOptionalSceneText(current.scene.annotation, next.scene.annotation)
            )
            statusMessage = "Combining Scenes \(current.originalSceneNumber) and \(next.originalSceneNumber)…"
            try await baserowSceneService.updateScene(
                combined, rowID: current.rowID, baseURL: baserowBaseURL,
                token: baserowToken, tableID: baserowTableID,
                part: current.part, scriptID: scriptID, sceneNumber: current.originalSceneNumber
            )
            combinedWasSaved = true
            try await baserowSceneService.deleteScene(
                rowID: next.rowID, baseURL: baserowBaseURL, token: baserowToken, tableID: baserowTableID
            )
            nextWasDeleted = true

            let laterRecords = scriptRecords
                .filter { $0.originalSceneNumber > next.originalSceneNumber }
                .sorted { $0.originalSceneNumber < $1.originalSceneNumber }
            for record in laterRecords {
                try await baserowSceneService.updateSceneNumber(
                    rowID: record.rowID, sceneNumber: record.originalSceneNumber - 1,
                    baseURL: baserowBaseURL, token: baserowToken, tableID: baserowTableID
                )
                renumberedRecords.append(record)
            }

            baserowRevision = ""
            await syncBaserowScenes(force: true)
            await registerBaserowUndo(
                actionName: "Combine Scenes", scriptID: scriptID,
                before: undoSnapshot, preferredSceneNumber: current.originalSceneNumber
            )
            statusMessage = "Scenes combined. \(scriptSceneProgress)"
        } catch {
            for record in renumberedRecords.reversed() {
                try? await baserowSceneService.updateSceneNumber(
                    rowID: record.rowID, sceneNumber: record.originalSceneNumber,
                    baseURL: baserowBaseURL, token: baserowToken, tableID: baserowTableID
                )
            }
            if nextWasDeleted, let next = nextRecord {
                _ = try? await baserowSceneService.createScene(
                    sceneNumber: next.originalSceneNumber,
                    narration: next.scene.narration, onScreen: next.scene.onScreen,
                    annotation: next.scene.annotation, code: next.scene.code,
                    part: next.part, scriptID: scriptID,
                    baseURL: baserowBaseURL, token: baserowToken, tableID: baserowTableID
                )
            }
            if combinedWasSaved, let original = originalRecord {
                try? await baserowSceneService.updateScene(
                    original.scene, rowID: original.rowID, baseURL: baserowBaseURL,
                    token: baserowToken, tableID: baserowTableID,
                    part: original.part, scriptID: scriptID, sceneNumber: original.originalSceneNumber
                )
            }
            baserowRevision = ""
            await syncBaserowScenes(force: true)
            statusMessage = "Baserow combine failed: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    func separateBaserowScene(sceneID: String) async {
        guard scriptInputFormat == .baserow,
              let rowID = baserowRowIDsBySceneID[sceneID],
              let scriptID = baserowScriptIDsBySceneID[sceneID] else {
            statusMessage = "The selected Baserow scene could not be identified."
            return
        }
        if isBaserowSyncing { await syncBaserowScenes(force: true) }

        var originalRecord: BaserowSceneRecord?
        var renumberedRecords: [BaserowSceneRecord] = []
        var createdRowIDs: [Int] = []
        var originalWasSaved = false
        do {
            let records = try await baserowSceneService.fetchScenes(
                baseURL: baserowBaseURL, token: baserowToken, tableID: baserowTableID
            )
            guard let original = records.first(where: { $0.rowID == rowID && $0.scriptIDs.contains(scriptID) }) else {
                statusMessage = "That Baserow scene no longer exists. Refreshing scenes…"
                await syncBaserowScenes(force: true)
                return
            }
            let undoSnapshot = records.filter { $0.scriptIDs.contains(scriptID) }
            originalRecord = original
            let sentences = ScriptSceneSplitter.scenes(from: original.scene.narration)
            guard sentences.count >= 2 else {
                statusMessage = "This narration contains only one sentence."
                return
            }

            statusMessage = "Separating Scene \(original.originalSceneNumber) into \(sentences.count) scenes…"
            let shift = sentences.count - 1
            let laterRecords = records
                .filter { $0.scriptIDs.contains(scriptID) && $0.originalSceneNumber > original.originalSceneNumber }
                .sorted { $0.originalSceneNumber > $1.originalSceneNumber }
            for record in laterRecords {
                try await baserowSceneService.updateSceneNumber(
                    rowID: record.rowID, sceneNumber: record.originalSceneNumber + shift,
                    baseURL: baserowBaseURL, token: baserowToken, tableID: baserowTableID
                )
                renumberedRecords.append(record)
            }

            let firstScene = NarrationScene(
                id: original.scene.id, sceneNumber: original.scene.sceneNumber,
                narration: sentences[0], onScreen: original.scene.onScreen,
                code: original.scene.code, annotation: original.scene.annotation
            )
            try await baserowSceneService.updateScene(
                firstScene, rowID: original.rowID, baseURL: baserowBaseURL,
                token: baserowToken, tableID: baserowTableID,
                part: original.part, scriptID: scriptID, sceneNumber: original.originalSceneNumber
            )
            originalWasSaved = true

            for (offset, sentence) in sentences.dropFirst().enumerated() {
                let createdRowID = try await baserowSceneService.createScene(
                    sceneNumber: original.originalSceneNumber + offset + 1,
                    narration: sentence, onScreen: original.scene.onScreen,
                    annotation: original.scene.annotation, code: nil,
                    part: original.part, scriptID: scriptID,
                    baseURL: baserowBaseURL, token: baserowToken, tableID: baserowTableID
                )
                createdRowIDs.append(createdRowID)
            }

            baserowRevision = ""
            await syncBaserowScenes(force: true)
            await registerBaserowUndo(
                actionName: "Separate Scene", scriptID: scriptID,
                before: undoSnapshot, preferredSceneNumber: original.originalSceneNumber
            )
            statusMessage = "Scene separated into \(sentences.count) scenes. \(scriptSceneProgress)"
        } catch {
            for createdRowID in createdRowIDs {
                try? await baserowSceneService.deleteScene(
                    rowID: createdRowID, baseURL: baserowBaseURL, token: baserowToken, tableID: baserowTableID
                )
            }
            if originalWasSaved, let original = originalRecord {
                try? await baserowSceneService.updateScene(
                    original.scene, rowID: original.rowID, baseURL: baserowBaseURL,
                    token: baserowToken, tableID: baserowTableID,
                    part: original.part, scriptID: scriptID, sceneNumber: original.originalSceneNumber
                )
            }
            for record in renumberedRecords.reversed() {
                try? await baserowSceneService.updateSceneNumber(
                    rowID: record.rowID, sceneNumber: record.originalSceneNumber,
                    baseURL: baserowBaseURL, token: baserowToken, tableID: baserowTableID
                )
            }
            baserowRevision = ""
            await syncBaserowScenes(force: true)
            statusMessage = "Baserow separation failed: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    private static func joinSceneText(_ first: String, _ second: String, separator: String) -> String {
        [first, second]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: separator)
    }

    private static func joinOptionalSceneText(_ first: String?, _ second: String?) -> String? {
        let result = joinSceneText(first ?? "", second ?? "", separator: "\n")
        return result.isEmpty ? nil : result
    }

    func undoLastBaserowOperation() async {
        guard let entry = baserowUndoEntry, !isUndoingBaserowOperation else { return }
        isUndoingBaserowOperation = true
        defer { isUndoingBaserowOperation = false }
        stopSceneManagerNarrationQueue()

        do {
            let allRecords = try await baserowSceneService.fetchScenes(
                baseURL: baserowBaseURL, token: baserowToken, tableID: baserowTableID
            )
            let current = allRecords.filter { $0.scriptIDs.contains(entry.scriptID) }
            guard Self.baserowUndoSignature(current) == entry.expectedAfterSignature else {
                clearBaserowUndo()
                statusMessage = "Undo is unavailable because this script changed after \(entry.actionName)."
                return
            }

            statusMessage = "Undoing \(entry.actionName)…"
            try await restoreBaserowScript(from: current, to: entry.before, scriptID: entry.scriptID)
            clearBaserowUndo()
            baserowRevision = ""
            await syncBaserowScenes(force: true)
            if let index = loadedChapter?.scenes.firstIndex(where: {
                baserowOriginalSceneNumbersBySceneID[$0.id] == entry.preferredSceneNumber
            }) {
                currentSceneIndex = index
            }
            statusMessage = "\(entry.actionName) undone. \(scriptSceneProgress)"
        } catch {
            baserowRevision = ""
            await syncBaserowScenes(force: true)
            statusMessage = "Baserow undo failed: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    private func registerBaserowUndo(
        actionName: String,
        scriptID: Int,
        before: [BaserowSceneRecord],
        preferredSceneNumber: Int
    ) async {
        guard let allRecords = try? await baserowSceneService.fetchScenes(
            baseURL: baserowBaseURL, token: baserowToken, tableID: baserowTableID
        ) else {
            clearBaserowUndo()
            return
        }
        let after = allRecords.filter { $0.scriptIDs.contains(scriptID) }
        baserowUndoEntry = BaserowUndoEntry(
            actionName: actionName,
            scriptID: scriptID,
            before: before,
            expectedAfterSignature: Self.baserowUndoSignature(after),
            preferredSceneNumber: preferredSceneNumber
        )
        baserowUndoActionName = actionName
    }

    private func clearBaserowUndo() {
        baserowUndoEntry = nil
        baserowUndoActionName = nil
    }

    private func restoreBaserowScript(
        from current: [BaserowSceneRecord],
        to target: [BaserowSceneRecord],
        scriptID: Int
    ) async throws {
        let targetIDs = Set(target.map(\.rowID))
        for record in current where !targetIDs.contains(record.rowID) {
            try await baserowSceneService.deleteScene(
                rowID: record.rowID, baseURL: baserowBaseURL,
                token: baserowToken, tableID: baserowTableID
            )
        }

        let currentIDs = Set(current.map(\.rowID))
        for record in target.sorted(by: { $0.originalSceneNumber < $1.originalSceneNumber }) {
            if currentIDs.contains(record.rowID) {
                try await baserowSceneService.updateScene(
                    record.scene, rowID: record.rowID, baseURL: baserowBaseURL,
                    token: baserowToken, tableID: baserowTableID,
                    part: record.part, scriptIDs: record.scriptIDs,
                    sceneNumber: record.originalSceneNumber
                )
            } else {
                _ = try await baserowSceneService.createScene(
                    sceneNumber: record.originalSceneNumber,
                    narration: record.scene.narration, onScreen: record.scene.onScreen,
                    annotation: record.scene.annotation, code: record.scene.code,
                    part: record.part, scriptID: record.scriptIDs.first ?? scriptID,
                    scriptIDs: record.scriptIDs,
                    baseURL: baserowBaseURL, token: baserowToken, tableID: baserowTableID
                )
            }
        }
    }

    private static func baserowUndoSignature(_ records: [BaserowSceneRecord]) -> String {
        records.sorted { $0.rowID < $1.rowID }.map { record in
            let code = record.scene.code
            return [
                String(record.rowID), String(record.originalSceneNumber),
                String(reflecting: record.part), record.scriptIDs.sorted().map(String.init).joined(separator: ","),
                String(reflecting: record.scene.narration), String(reflecting: record.scene.onScreen),
                String(reflecting: record.scene.annotation), String(reflecting: code?.text),
                String(reflecting: code?.language), String(reflecting: code?.targetFile),
                String(reflecting: code?.instruction)
            ].joined(separator: "|")
        }.joined(separator: "\n")
    }

    private func syncBaserowScenes(force: Bool) async {
        guard hasBaserowConfiguration else { return }
        if isBaserowSyncing {
            baserowSyncRequested = true
            await withCheckedContinuation { continuation in
                baserowSyncWaiters.append(continuation)
            }
            return
        }

        isBaserowSyncing = true
        repeat {
            baserowSyncRequested = false
            await performBaserowSync(force: force)
        } while baserowSyncRequested
        isBaserowSyncing = false

        let waiters = baserowSyncWaiters
        baserowSyncWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func performBaserowSync(force: Bool) async {
        do {
            let scripts = try await baserowSceneService.fetchScripts(
                baseURL: baserowBaseURL,
                token: baserowToken,
                tableID: baserowScriptsTableID
            )
            let allRecords = try await baserowSceneService.fetchScenes(
                baseURL: baserowBaseURL,
                token: baserowToken,
                tableID: baserowTableID
            )
            baserowScripts = scripts
            if baserowSelectedScriptID == 0 || !scripts.contains(where: { $0.rowID == baserowSelectedScriptID }) {
                baserowSelectedScriptID = scripts.first?.rowID ?? 0
            }
            let selectedScriptID = baserowSelectedScriptID
            if selectedScriptID != 0 {
                let scriptRecords = allRecords
                    .filter { $0.scriptIDs.contains(selectedScriptID) }
                    .sorted { $0.originalSceneNumber < $1.originalSceneNumber }
                for (index, record) in scriptRecords.enumerated()
                where record.originalSceneNumber != index + 1 {
                    throw BaserowSceneError.invalidScenes(
                        "Script scenes must use continuous Scene Numbers. Expected \(index + 1), found \(record.originalSceneNumber)."
                    )
                }
            }
            let availableParts = allRecords
                .filter { selectedScriptID == 0 || $0.scriptIDs.contains(selectedScriptID) }
                .compactMap(\.part)
            baserowPartOptions = Self.orderedBaserowParts(from: availableParts)
            if !baserowPartFilter.isEmpty, !baserowPartOptions.contains(baserowPartFilter) {
                baserowPartFilter = ""
            }
            let matchingRecords = allRecords.filter { record in
                (selectedScriptID == 0 || record.scriptIDs.contains(selectedScriptID))
                    && (baserowPartFilter.isEmpty || record.part == baserowPartFilter)
            }
            let sourceRevision = scripts.map { "\($0.rowID):\($0.lastEditedTime)" }.joined(separator: "|")
                + "#" + allRecords.map { "\($0.rowID):\($0.lastEditedTime)" }.joined(separator: "|")
            let revision = "\(selectedScriptID)|\(baserowPartFilter)|\(sourceRevision)"
            if !force, revision == baserowRevision { return }

            if matchingRecords.isEmpty {
                loadedChapter = nil
                loadedChapterURL = nil
                baserowRowIDsBySceneID = [:]
                baserowOriginalSceneNumbersBySceneID = [:]
                baserowPartBySceneID = [:]
                baserowScriptIDsBySceneID = [:]
                baserowLastEditedBySceneID = [:]
                baserowRevision = revision
                isBaserowConnected = true
                scriptInputFormat = .baserow
                scriptModeEnabled = true
                readsTypedTextInsteadOfClipboard = true
                refreshScriptScenes()
                statusMessage = allRecords.isEmpty
                    ? "Baserow connected. No scenes yet."
                    : "Baserow connected. No scenes match this script or Part filter."
                presenterOverlayController?.updateLayout()
                return
            }

            let normalizedRecords = matchingRecords.enumerated().map { index, record in
                BaserowSceneRecord(
                    rowID: record.rowID,
                    originalSceneNumber: record.originalSceneNumber,
                    part: record.part,
                    scriptIDs: record.scriptIDs,
                    lastEditedTime: record.lastEditedTime,
                    scene: NarrationScene(
                        id: record.scene.id,
                        sceneNumber: index + 1,
                        narration: record.scene.narration,
                        onScreen: record.scene.onScreen,
                        code: record.scene.code,
                        annotation: record.scene.annotation
                    )
                )
            }
            let chapter = NarrationChapter(
                schemaVersion: NarrationChapterLoader.supportedSchemaVersion,
                chapterNumber: 1,
                chapterTitle: baserowScripts.first(where: { $0.rowID == selectedScriptID })?.title ?? "Baserow Scenes",
                scenes: normalizedRecords.map(\.scene)
            )
            try NarrationChapterLoader.validate(chapter, allowsEmptySceneContent: true)
            let previousSceneID = currentNarrationScene?.id
            loadedChapter = chapter
            loadedChapterURL = nil
            baserowRowIDsBySceneID = Dictionary(uniqueKeysWithValues: normalizedRecords.map { ($0.scene.id, $0.rowID) })
            baserowOriginalSceneNumbersBySceneID = Dictionary(uniqueKeysWithValues: normalizedRecords.map { ($0.scene.id, $0.originalSceneNumber) })
            baserowPartBySceneID = Dictionary(uniqueKeysWithValues: normalizedRecords.compactMap { record in
                guard let part = record.part else { return nil }
                return (record.scene.id, part)
            })
            baserowScriptIDsBySceneID = Dictionary(uniqueKeysWithValues: normalizedRecords.compactMap { record in
                guard let scriptID = record.scriptIDs.first else { return nil }
                return (record.scene.id, scriptID)
            })
            baserowLastEditedBySceneID = Dictionary(uniqueKeysWithValues: normalizedRecords.compactMap { record in
                guard let date = BaserowSceneService.date(from: record.lastEditedTime) else { return nil }
                return (record.scene.id, date)
            })
            baserowRevision = revision
            isBaserowConnected = true
            scriptInputFormat = .baserow
            scriptModeEnabled = true
            readsTypedTextInsteadOfClipboard = true
            refreshScriptScenes()
            if let previousSceneID, let index = chapter.scenes.firstIndex(where: { $0.id == previousSceneID }) {
                currentSceneIndex = index
            }
            saveBaserowCache(chapter)
            statusMessage = "Baserow synced. \(scriptSceneProgress)"
            presenterOverlayController?.updateLayout()
        } catch {
            if !isBaserowConnected { restoreBaserowCache() }
            statusMessage = "Baserow sync failed: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    private static func orderedBaserowParts(from values: [String]) -> [String] {
        let unique = Array(Set(values))
        let preferred = ["Introduction", "Chapter 1", "Chapter 2", "Chapter 3", "Chapter 4", "Chapter 5", "Conclusion"]
        return unique.sorted { lhs, rhs in
            let leftIndex = preferred.firstIndex(of: lhs) ?? preferred.count
            let rightIndex = preferred.firstIndex(of: rhs) ?? preferred.count
            return leftIndex == rightIndex
                ? lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
                : leftIndex < rightIndex
        }
    }

    private func saveBaserowCache(_ chapter: NarrationChapter) {
        guard let data = try? JSONEncoder.narrationPilot.encode(chapter) else { return }
        try? FileManager.default.createDirectory(at: baserowCacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: baserowCacheURL, options: .atomic)
    }

    private func restoreBaserowCache() {
        guard let data = try? Data(contentsOf: baserowCacheURL),
              let chapter = try? NarrationChapterLoader.decode(data, allowsEmptySceneContent: true) else { return }
        loadedChapter = chapter
        loadedChapterURL = nil
        scriptInputFormat = .baserow
        scriptModeEnabled = true
        refreshScriptScenes()
        statusMessage = "Using cached Baserow scenes offline."
    }

    private var baserowCacheURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Narration Pilot", isDirectory: true).appendingPathComponent("baserow-scenes-cache.json")
    }

    func chooseChapterJSON() {
        let panel = NSOpenPanel()
        panel.title = "Import Chapter JSON"
        panel.prompt = "Import"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]

        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                Task { @MainActor in
                    self?.importChapterJSON(from: url, confirmsReplacement: true)
                }
            }
        }
    }

    func reloadChapterJSON() {
        guard let loadedChapterURL else {
            statusMessage = "No chapter JSON is loaded."
            return
        }
        importChapterJSON(from: loadedChapterURL, confirmsReplacement: false)
    }

    func restoreLastChapterJSONIfAvailable() {
        guard let path = defaults.string(forKey: Self.lastChapterJSONPathKey),
              !path.isEmpty,
              FileManager.default.fileExists(atPath: path) else {
            return
        }

        importChapterJSON(from: URL(fileURLWithPath: path), confirmsReplacement: false)
    }

    func clearChapterJSON() {
        stopSpeechForSceneNavigation()
        chapterFileWatcher.stop()
        pendingChapterReloadURL = nil
        loadedChapter = nil
        loadedChapterURL = nil
        defaults.removeObject(forKey: Self.lastChapterJSONPathKey)
        currentSceneIndex = 0
        refreshScriptScenes()
        statusMessage = "Chapter JSON cleared."
        presenterOverlayController?.updateLayout()
    }

    func importChapterJSON(from url: URL, confirmsReplacement: Bool) {
        if confirmsReplacement,
           let loadedChapterURL,
           loadedChapterURL.standardizedFileURL != url.standardizedFileURL {
            let alert = NSAlert()
            alert.messageText = "Replace the loaded chapter?"
            alert.informativeText = "Importing this file will replace the current JSON chapter. Your text script will remain unchanged."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        do {
            let chapter = try NarrationChapterLoader.load(from: url)
            stopSpeechForSceneNavigation()
            pendingChapterReloadURL = nil
            loadedChapter = chapter
            loadedChapterURL = url.standardizedFileURL
            defaults.set(url.standardizedFileURL.path, forKey: Self.lastChapterJSONPathKey)
            scriptInputFormat = .json
            scriptModeEnabled = true
            readsTypedTextInsteadOfClipboard = true
            currentSceneIndex = 0
            refreshScriptScenes()
            statusMessage = "Loaded Chapter \(chapter.chapterNumber): \(chapter.chapterTitle)"
            presenterOverlayController?.updateLayout()
            refreshPresenterOverlayVisibility()
            startWatchingChapterFile(at: url.standardizedFileURL)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusMessage = message
            let alert = NSAlert()
            alert.messageText = "Could Not Import Chapter JSON"
            alert.informativeText = message
            alert.alertStyle = .critical
            alert.runModal()
        }
    }

    private func startWatchingChapterFile(at url: URL) {
        chapterFileWatcher.start(url: url) { [weak self] changedURL in
            self?.handleChapterFileChange(changedURL)
        }
    }

    private func handleChapterFileChange(_ url: URL) {
        if speechState == .speaking || speechState == .paused || speechState == .stopping {
            pendingChapterReloadURL = url
            statusMessage = "Chapter changed on disk. Reloading after speech finishes…"
            return
        }

        reloadChapterFromDisk(url)
    }

    private func reloadChapterFromDisk(_ url: URL) {
        let previousSceneID = currentNarrationScene?.id

        do {
            let chapter = try NarrationChapterLoader.load(from: url)
            loadedChapter = chapter
            loadedChapterURL = url.standardizedFileURL
            refreshScriptScenes()

            if let previousSceneID,
               let preservedIndex = chapter.scenes.firstIndex(where: { $0.id == previousSceneID }) {
                currentSceneIndex = preservedIndex
            } else {
                currentSceneIndex = 0
            }

            statusMessage = "Chapter updated from disk. \(scriptSceneProgress)"
            presenterOverlayController?.updateLayout()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusMessage = "Chapter update rejected: \(message)"
        }
    }

    func saveEditedChapterJSON(_ text: String) {
        if scriptInputFormat == .baserow, isBaserowConnected {
            saveEditedBaserowChapter(text)
            return
        }
        if scriptInputFormat == .json, isNotionConnected {
            saveEditedNotionChapter(text)
            return
        }
        guard let url = loadedChapterURL else {
            statusMessage = "No chapter JSON is loaded."
            return
        }

        do {
            let data = Data(text.utf8)
            let chapter = try NarrationChapterLoader.decode(data)
            let backupURL = url.deletingPathExtension().appendingPathExtension("json.backup")
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.copyItem(at: url, to: backupURL)
                if FileManager.default.fileExists(atPath: backupURL.path) {
                    try? FileManager.default.removeItem(at: backupURL)
                    try FileManager.default.copyItem(at: url, to: backupURL)
                }
            }
            try data.write(to: url, options: .atomic)
            loadedChapter = chapter
            refreshScriptScenes()
            statusMessage = "Chapter JSON saved."
        } catch {
            statusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func saveEditedNotionChapter(_ text: String) {
        do {
            let chapter = try NarrationChapterLoader.decode(Data(text.utf8))
            guard let oldChapter = loadedChapter,
                  let changed = chapter.scenes.first(where: { scene in
                      oldChapter.scenes.first(where: { $0.id == scene.id }) != scene
                  }),
                  let pageID = notionPageIDsBySceneID[changed.id] else {
                statusMessage = "No Notion scene change found."
                return
            }
            loadedChapter = chapter
            refreshScriptScenes()
            saveNotionCache(chapter)
            statusMessage = "Saving Scene \(changed.sceneNumber) to Notion…"
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.notionSceneService.updateScene(changed, pageID: pageID, token: self.notionToken)
                    self.notionRevision = ""
                    self.statusMessage = "Scene \(changed.sceneNumber) saved to Notion."
                } catch {
                    self.statusMessage = "Notion save failed: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
                }
            }
        } catch {
            statusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func saveEditedBaserowChapter(_ text: String) {
        do {
            let chapter = try NarrationChapterLoader.decode(
                Data(text.utf8),
                allowsEmptySceneContent: true
            )
            guard let oldChapter = loadedChapter,
                  let changed = chapter.scenes.first(where: { scene in
                      oldChapter.scenes.first(where: { $0.id == scene.id }) != scene
                  }),
                  let rowID = baserowRowIDsBySceneID[changed.id] else {
                statusMessage = "No Baserow scene change found."
                return
            }
            loadedChapter = chapter
            refreshScriptScenes()
            saveBaserowCache(chapter)
            statusMessage = "Saving Scene \(changed.sceneNumber) to Baserow…"
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.baserowSceneService.updateScene(
                        changed,
                        rowID: rowID,
                        baseURL: self.baserowBaseURL,
                        token: self.baserowToken,
                        tableID: self.baserowTableID,
                        part: self.baserowPartBySceneID[changed.id],
                        scriptID: self.baserowScriptIDsBySceneID[changed.id],
                        sceneNumber: self.baserowOriginalSceneNumbersBySceneID[changed.id]
                    )
                    self.baserowRevision = ""
                    self.statusMessage = "Scene \(changed.sceneNumber) saved to Baserow."
                } catch {
                    self.statusMessage = "Baserow save failed: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
                }
            }
        } catch {
            statusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func applyPendingChapterReloadIfNeeded() {
        guard let url = pendingChapterReloadURL else { return }
        pendingChapterReloadURL = nil
        reloadChapterFromDisk(url)
    }

    func openCurrentSceneEditor() {
        if !scriptModeEnabled {
            scriptModeEnabled = true
        }

        if scriptInputFormat == .baserow, hasBaserowConfiguration {
            Task { [weak self] in
                guard let self else { return }
                await self.syncBaserowScenes(force: true)
                self.refreshScriptScenes()
                self.sceneEditorController?.show()
            }
        } else if scriptInputFormat == .json, hasNotionConfiguration {
            Task { [weak self] in
                guard let self else { return }
                await self.syncNotionScenes(force: true)
                self.refreshScriptScenes()
                self.sceneEditorController?.show()
            }
        } else {
            refreshScriptScenes()
            sceneEditorController?.show()
        }
    }

    func toggleCurrentSceneEditor() {
        if !scriptModeEnabled {
            scriptModeEnabled = true
        }

        if sceneEditorController?.isVisible == true {
            sceneEditorController?.toggle()
        } else if scriptInputFormat == .baserow, hasBaserowConfiguration {
            Task { [weak self] in
                guard let self else { return }
                await self.syncBaserowScenes(force: true)
                self.refreshScriptScenes()
                self.sceneEditorController?.show()
            }
        } else if scriptInputFormat == .json, hasNotionConfiguration {
            Task { [weak self] in
                guard let self else { return }
                await self.syncNotionScenes(force: true)
                self.refreshScriptScenes()
                self.sceneEditorController?.show()
            }
        } else {
            refreshScriptScenes()
            sceneEditorController?.toggle()
        }
    }

    func saveCurrentSceneEdit(_ editedText: String) {
        let replacement = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !replacement.isEmpty else {
            statusMessage = "Current scene cannot be empty."
            return
        }

        if manualSceneOverride != nil {
            var scenes = scriptScenes
            if scenes.indices.contains(currentSceneIndex) {
                scenes[currentSceneIndex] = replacement
            } else {
                scenes = [replacement]
            }

            saveSceneManagerScenes(scenes, selectedIndex: currentSceneIndex)
            return
        }

        let scenes = ScriptSceneSplitter.sceneRanges(from: typedText)
        guard scenes.indices.contains(currentSceneIndex) else {
            typedText = replacement
            refreshScriptScenes()
            currentSceneIndex = 0
            statusMessage = "Current scene created."
            presenterOverlayController?.updateLayout()
            return
        }

        let currentIndex = currentSceneIndex
        var normalizedScript = ScriptSceneSplitter.normalized(typedText)
        normalizedScript.replaceSubrange(scenes[currentIndex].range, with: replacement)
        typedText = normalizedScript
        refreshScriptScenes()
        currentSceneIndex = min(currentIndex, max(scriptScenes.count - 1, 0))
        statusMessage = "Current scene updated."
        presenterOverlayController?.updateLayout()
    }

    func saveSceneManagerScenes(_ scenes: [String], selectedIndex: Int) {
        let cleanedScenes = scenes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !cleanedScenes.isEmpty else {
            manualSceneOverride = nil
            manualSceneOverrideSource = nil
            typedText = ""
            refreshScriptScenes()
            currentSceneIndex = 0
            statusMessage = "Script cleared."
            presenterOverlayController?.updateLayout()
            return
        }

        let updatedScript = cleanedScenes.joined(separator: "\n\n")
        manualSceneOverride = cleanedScenes
        manualSceneOverrideSource = ScriptSceneSplitter.normalized(updatedScript)
        typedText = updatedScript
        refreshScriptScenes()
        currentSceneIndex = min(max(selectedIndex, 0), max(scriptScenes.count - 1, 0))
        statusMessage = "Scenes updated."
        presenterOverlayController?.updateLayout()
    }

    func selectSceneForEditing(_ index: Int) {
        refreshScriptScenes()
        guard scriptScenes.indices.contains(index) else {
            return
        }

        currentSceneIndex = index
        statusMessage = scriptSceneProgress
        presenterOverlayController?.updateLayout()
    }

    func previewCurrentSceneNarration() {
        cancelSceneManagerNarrationQueue(stopSpeech: false)
        guard let narration = currentNarrationScene?.narration
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !narration.isEmpty else {
            stopSpeechForSceneNavigation()
            return
        }

        shouldAdvanceScriptSceneAfterSpeech = false
        cancelPendingReadSequence()
        statusMessage = "Reading narration for \(scriptSceneProgress)…"
        ttsManager.speak(
            text: narration,
            speedMultiplier: speedMultiplier,
            voiceIdentifier: selectedVoiceIdentifier
        )
    }

    func playSceneManagerNarrations(_ scenes: [NarrationScene]) {
        let queue = scenes.compactMap { scene -> (sceneID: String, narration: String)? in
            let narration = scene.narration.trimmingCharacters(in: .whitespacesAndNewlines)
            return narration.isEmpty ? nil : (scene.id, narration)
        }
        guard !queue.isEmpty else {
            statusMessage = "There are no narrations to play in this selection."
            return
        }

        stopReading()
        sceneManagerNarrationQueue = queue
        isSceneManagerNarrationQueuePlaying = true
        playNextSceneManagerNarration()
    }

    func stopSceneManagerNarrationQueue() {
        cancelSceneManagerNarrationQueue(stopSpeech: true)
        statusMessage = SpeechState.idle.label
    }

    private func playNextSceneManagerNarration() {
        guard isSceneManagerNarrationQueuePlaying,
              !sceneManagerNarrationQueue.isEmpty else {
            cancelSceneManagerNarrationQueue(stopSpeech: false)
            statusMessage = "Finished playing the selected narrations."
            return
        }

        let next = sceneManagerNarrationQueue.removeFirst()
        sceneManagerNarrationSceneID = next.sceneID
        statusMessage = "Playing narration (sceneManagerNarrationQueue.count + 1) remaining…"
        ttsManager.speak(
            text: next.narration,
            speedMultiplier: speedMultiplier,
            voiceIdentifier: selectedVoiceIdentifier
        )
    }

    private func cancelSceneManagerNarrationQueue(stopSpeech: Bool) {
        let wasPlaying = isSceneManagerNarrationQueuePlaying
        sceneManagerNarrationQueue = []
        sceneManagerNarrationSceneID = nil
        isSceneManagerNarrationQueuePlaying = false
        if stopSpeech, wasPlaying,
           speechState == .speaking || speechState == .paused || speechState == .stopping {
            ttsManager.stop()
        }
    }

    func refreshScriptScenes() {
        if scriptInputFormat.usesStructuredScenes {
            manualSceneOverride = nil
            manualSceneOverrideSource = nil
            scriptScenes = loadedChapter?.scenes.map { scene in
                scene.narration.trimmingCharacters(in: .whitespacesAndNewlines)
            } ?? []
            if scriptScenes.isEmpty {
                currentSceneIndex = 0
            } else {
                currentSceneIndex = min(currentSceneIndex, scriptScenes.count - 1)
            }
            return
        }

        let normalizedText = ScriptSceneSplitter.normalized(typedText)
        if let manualSceneOverride,
           manualSceneOverrideSource == normalizedText {
            scriptScenes = manualSceneOverride
            if scriptScenes.isEmpty {
                currentSceneIndex = 0
            } else {
                currentSceneIndex = min(currentSceneIndex, scriptScenes.count - 1)
            }
            return
        }

        manualSceneOverride = nil
        manualSceneOverrideSource = nil
        scriptScenes = ScriptSceneSplitter.scenes(from: typedText)
        if scriptScenes.isEmpty {
            currentSceneIndex = 0
        } else {
            currentSceneIndex = min(currentSceneIndex, scriptScenes.count - 1)
        }
    }

    func refreshPresenterOverlayVisibility() {
        presenterOverlayController?.updateVisibility()
    }

    func openShortcutTriggerAccessibilitySettings() {
        ShortcutTriggerService.openAccessibilitySettings()
        refreshShortcutTriggerAccessibilityStatus()
    }

    func refreshShortcutTriggerAccessibilityStatus(promptIfNeeded: Bool = false) {
        if promptIfNeeded {
            ShortcutTriggerService.requestAccessibilityTrustPrompt()
        }

        isShortcutTriggerAccessibilityTrusted = ShortcutTriggerService.isAccessibilityTrusted
    }

    func requestShortcutTriggerAccessibilityPermission() {
        defaults.set(true, forKey: Self.accessibilityLaunchPromptAttemptedKey)
        ShortcutTriggerService.requestAccessibilityTrustPrompt()
        refreshShortcutTriggerAccessibilityStatus()
    }

    func checkAccessibilityPermissionAtLaunch() {
        refreshShortcutTriggerAccessibilityStatus()
        guard !isShortcutTriggerAccessibilityTrusted,
              !defaults.bool(forKey: Self.accessibilityLaunchPromptAttemptedKey) else {
            return
        }

        defaults.set(true, forKey: Self.accessibilityLaunchPromptAttemptedKey)
        statusMessage = "Accessibility permission is needed for external shortcuts and activity detection."
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            ShortcutTriggerService.requestAccessibilityTrustPrompt()
            self?.refreshShortcutTriggerAccessibilityStatus()
        }
    }

    func recheckAccessibilityPermission() {
        let wasTrusted = isShortcutTriggerAccessibilityTrusted
        refreshShortcutTriggerAccessibilityStatus()
        if !wasTrusted, isShortcutTriggerAccessibilityTrusted {
            statusMessage = "Accessibility permission granted."
        }
    }

    func updateRecordingTriggerShortcut(_ shortcut: TriggerShortcut) {
        recordingTriggerShortcut = shortcut

        guard let data = try? JSONEncoder().encode(shortcut) else {
            return
        }

        defaults.set(data, forKey: Self.recordingShortcutValueKey)
    }

    func clearRecordingTriggerShortcut() {
        recordingTriggerShortcut = nil
        defaults.removeObject(forKey: Self.recordingShortcutValueKey)
    }

    func togglePresenterOverlay() {
        guard scriptModeEnabled else {
            statusMessage = "Turn on Script mode to use presenter overlay."
            return
        }

        showPresenterOverlay.toggle()
        statusMessage = showPresenterOverlay ? "Presenter overlay shown." : "Presenter overlay hidden."
    }

    func resetPresenterOverlayDefaults() {
        presenterOverlayOpacity = Self.defaultPresenterOverlayOpacity
        presenterOverlayWidth = Self.defaultPresenterOverlayWidth
        presenterOverlayHeight = Self.defaultPresenterOverlayHeight
        presenterOverlayBottomOffset = Self.defaultPresenterOverlayBottomOffset
        presenterOverlayHorizontalOffset = Self.defaultPresenterOverlayHorizontalOffset
        presenterOverlayCurrentFontSize = Self.defaultPresenterOverlayCurrentFontSize
        presenterOverlaySideFontSize = Self.defaultPresenterOverlaySideFontSize
        presenterOverlayCurrentTextOpacity = Self.defaultPresenterOverlayCurrentTextOpacity
        presenterOverlaySecondaryTextOpacity = Self.defaultPresenterOverlaySecondaryTextOpacity
        presenterOverlayCurrentTextColor = .white
        presenterOverlaySecondaryTextColor = Color(red: 0.85, green: 0.87, blue: 0.91)
        presenterOverlayController?.updateLayout()
    }

    func goToPreviousScene() {
        guard scriptModeEnabled else {
            statusMessage = "Turn on Script mode to use scene controls."
            return
        }

        refreshScriptScenes()
        guard canGoToPreviousScene else {
            statusMessage = scriptScenes.isEmpty ? "Text field is empty." : "Already at first scene."
            return
        }

        stopSpeechForSceneNavigation()
        currentSceneIndex -= 1
        statusMessage = scriptSceneProgress
    }

    func goToNextScene() {
        guard scriptModeEnabled else {
            statusMessage = "Turn on Script mode to use scene controls."
            return
        }

        refreshScriptScenes()
        guard canGoToNextScene else {
            statusMessage = scriptScenes.isEmpty ? "Text field is empty." : "Already at last scene."
            return
        }

        stopSpeechForSceneNavigation()
        currentSceneIndex += 1
        statusMessage = scriptSceneProgress
    }

    func restartScript() {
        guard scriptModeEnabled else {
            statusMessage = "Turn on Script mode to use scene controls."
            return
        }

        stopSpeechForSceneNavigation()
        refreshScriptScenes()
        currentSceneIndex = 0
        statusMessage = scriptScenes.isEmpty ? "Text field is empty." : scriptSceneProgress
    }

    func replayCurrentScriptScene() {
        guard scriptModeEnabled else {
            statusMessage = "Turn on Script mode to use scene controls."
            return
        }

        readCurrentScriptSceneNow(
            advancesAfterSpeech: false,
            includesBracketedDirections: scriptInputFormat == .text
        )
    }

    func replayCurrentOnScreenOnly() {
        guard scriptModeEnabled, scriptInputFormat.usesStructuredScenes,
              let scene = currentNarrationScene else {
            statusMessage = "Load a Chapter JSON scene first."
            return
        }

        shouldAdvanceScriptSceneAfterSpeech = false
        beginReadSequence(
            actionBefore: .none,
            actionAfter: .none,
            delayBefore: 0,
            delayAfter: 0,
            waitsForNeonSpotlight: false,
            waitsForUserInactivity: false,
            readingStatus: "Reading on-screen direction for \(scriptSceneProgress)…"
        ) { [weak self] in
            guard let self else { return }
            self.ttsManager.speak(
                text: scene.onScreen,
                speedMultiplier: self.speedMultiplier,
                voiceIdentifier: self.selectedVoiceIdentifier
            )
        }
    }

    private func readClipboardNow(
        actionBefore: ExternalTriggerAction,
        actionAfter: ExternalTriggerAction,
        delayBefore: Double,
        delayAfter: Double,
        waitsForNeonSpotlight: Bool,
        waitsForUserInactivity: Bool,
        speedMultiplier: Double
    ) {
        guard let text = clipboardService.currentText() else {
            statusMessage = "Clipboard is empty."
            return
        }

        beginReadSequence(
            actionBefore: actionBefore,
            actionAfter: actionAfter,
            delayBefore: delayBefore,
            delayAfter: delayAfter,
            waitsForNeonSpotlight: waitsForNeonSpotlight,
            waitsForUserInactivity: waitsForUserInactivity,
            readingStatus: "Reading clipboard…"
        ) { [weak self] in
            guard let self else { return }
            self.ttsManager.speak(
                text: text,
                speedMultiplier: speedMultiplier,
                voiceIdentifier: self.selectedVoiceIdentifier
            )
        }
    }

    private func readTypedTextNow(
        actionBefore: ExternalTriggerAction,
        actionAfter: ExternalTriggerAction,
        delayBefore: Double,
        delayAfter: Double,
        waitsForNeonSpotlight: Bool,
        waitsForUserInactivity: Bool,
        speedMultiplier: Double
    ) {
        let text = clipboardService.normalize(typedText)
        guard !text.isEmpty else {
            statusMessage = "Text field is empty."
            return
        }

        beginReadSequence(
            actionBefore: actionBefore,
            actionAfter: actionAfter,
            delayBefore: delayBefore,
            delayAfter: delayAfter,
            waitsForNeonSpotlight: waitsForNeonSpotlight,
            waitsForUserInactivity: waitsForUserInactivity,
            readingStatus: "Reading typed text…"
        ) { [weak self] in
            guard let self else { return }
            self.ttsManager.speak(
                text: text,
                speedMultiplier: speedMultiplier,
                voiceIdentifier: self.selectedVoiceIdentifier
            )
        }
    }

    private func readCurrentScriptSceneNow() {
        readCurrentScriptSceneNow(
            advancesAfterSpeech: true,
            actionBefore: .none,
            actionAfter: .none,
            delayBefore: 0,
            delayAfter: 0,
            waitsForNeonSpotlight: false,
            waitsForUserInactivity: false,
            speedMultiplier: speedMultiplier
        )
    }

    private func readCurrentScriptSceneNow(
        actionBefore: ExternalTriggerAction,
        actionAfter: ExternalTriggerAction,
        delayBefore: Double,
        delayAfter: Double,
        waitsForNeonSpotlight: Bool,
        waitsForUserInactivity: Bool,
        speedMultiplier: Double
    ) {
        readCurrentScriptSceneNow(
            advancesAfterSpeech: true,
            actionBefore: actionBefore,
            actionAfter: actionAfter,
            delayBefore: delayBefore,
            delayAfter: delayAfter,
            waitsForNeonSpotlight: waitsForNeonSpotlight,
            waitsForUserInactivity: waitsForUserInactivity,
            speedMultiplier: speedMultiplier
        )
    }

    private func readCurrentScriptSceneNow(
        advancesAfterSpeech: Bool,
        includesBracketedDirections: Bool = false,
        actionBefore: ExternalTriggerAction = .none,
        actionAfter: ExternalTriggerAction = .none,
        delayBefore: Double = 0,
        delayAfter: Double = 0,
        waitsForNeonSpotlight: Bool = false,
        waitsForUserInactivity: Bool = false,
        speedMultiplier: Double? = nil
    ) {
        cancelSceneManagerNarrationQueue(stopSpeech: false)
        refreshScriptScenes()

        guard let scene = currentSceneText else {
            statusMessage = "Text field is empty."
            return
        }

        let spokenScene: String
        if !advancesAfterSpeech, let narrationScene = currentNarrationScene {
            spokenScene = JSONSceneReplayFormatter.spokenText(for: narrationScene)
        } else {
            spokenScene = scene
        }

        shouldAdvanceScriptSceneAfterSpeech = advancesAfterSpeech
        let readingStatus = advancesAfterSpeech ? "Reading \(scriptSceneProgress)…" : "Replaying \(scriptSceneProgress)…"
        let resolvedSpeedMultiplier = speedMultiplier ?? self.speedMultiplier
        beginReadSequence(
            actionBefore: actionBefore,
            actionAfter: actionAfter,
            delayBefore: delayBefore,
            delayAfter: delayAfter,
            waitsForNeonSpotlight: waitsForNeonSpotlight,
            waitsForUserInactivity: waitsForUserInactivity,
            readingStatus: readingStatus
        ) { [weak self] in
            guard let self else { return }
            if !advancesAfterSpeech, let narrationScene = self.currentNarrationScene {
                self.ttsManager.speakSequence(
                    texts: JSONSceneReplayFormatter.spokenParts(for: narrationScene),
                    pauseBetween: 1,
                    speedMultiplier: resolvedSpeedMultiplier,
                    voiceIdentifier: self.selectedVoiceIdentifier
                )
                return
            }
            self.ttsManager.speak(
                text: spokenScene,
                speedMultiplier: resolvedSpeedMultiplier,
                voiceIdentifier: self.selectedVoiceIdentifier,
                includesBracketedDirections: includesBracketedDirections
            )
        }
    }

    func stopReading() {
        cancelSceneManagerNarrationQueue(stopSpeech: false)
        shouldAdvanceScriptSceneAfterSpeech = false
        cancelPendingReadSequence()
        let wasIdle = speechState == .idle
        ttsManager.stop()
        if wasIdle {
            statusMessage = SpeechState.idle.label
        }
    }

    func togglePauseResume() {
        ttsManager.togglePauseResume()
    }

    func updateVoiceSelection(_ identifier: String) {
        selectedVoiceIdentifier = identifier.isEmpty ? nil : identifier
    }

    func previewRecordingCueSound(_ sound: RecordingCueSound) {
        sound.play()
    }

    func previewRecordingFailureCueSound() {
        playRecordingFailureCue()
    }

    private func stopSpeechForSceneNavigation() {
        shouldAdvanceScriptSceneAfterSpeech = false
        cancelPendingReadSequence()
        if speechState == .speaking || speechState == .paused || speechState == .stopping {
            ttsManager.stop()
        }
    }

    private func beginReadSequence(
        actionBefore: ExternalTriggerAction,
        actionAfter: ExternalTriggerAction,
        delayBefore: Double,
        delayAfter: Double,
        waitsForNeonSpotlight: Bool,
        waitsForUserInactivity: Bool,
        readingStatus: String,
        speak: @escaping @MainActor () -> Void
    ) {
        cancelPendingReadSequence()
        if speechState == .speaking || speechState == .paused || speechState == .stopping {
            ttsManager.stop()
        }

        let sequenceID = UUID()
        activeReadSequenceID = sequenceID
        externalTriggerActionAfterSpeech = actionAfter
        externalTriggerDelayAfterSpeech = actionAfter == .none ? 0 : Self.clampTriggerDelay(delayAfter)
        waitsForNeonSpotlightAfterSpeech = actionAfter == .ensurePaused
            && waitsForNeonSpotlight
        waitsForUserInactivityAfterSpeech = actionAfter == .ensurePaused
            && waitsForUserInactivity
        let resolvedDelayBefore = actionBefore == .none ? 0 : Self.clampTriggerDelay(delayBefore)
        pendingReadTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled,
                  let self,
                  self.activeReadSequenceID == sequenceID else {
                return
            }

            if actionBefore == .ensureRecording, self.recordingCueSoundsEnabled {
                self.recordingStartCueSound.play()
                if self.recordingStartCueSound != .none {
                    try? await Task.sleep(for: .seconds(self.recordingStartCueDelay))
                }
            }

            guard !Task.isCancelled, self.activeReadSequenceID == sequenceID else {
                return
            }

            let actionSucceeded = await self.performExternalTriggerAction(actionBefore)
            guard actionSucceeded else {
                if actionBefore == .ensureRecording {
                    self.playRecordingFailureCue()
                    self.statusMessage = "Recording did not start. Narration cancelled."
                }
                self.cancelPendingReadSequence()
                return
            }

            if resolvedDelayBefore > 0 {
                self.statusMessage = "Starting speech in \(Self.formattedDelay(resolvedDelayBefore)) seconds…"
                try? await Task.sleep(for: .seconds(resolvedDelayBefore))
            }

            guard !Task.isCancelled, self.activeReadSequenceID == sequenceID else {
                return
            }

            self.pendingReadTask = nil
            self.statusMessage = readingStatus
            speak()
        }
    }

    private func cancelPendingReadSequence() {
        pendingReadTask?.cancel()
        pendingReadTask = nil
        activeReadSequenceID = nil
        externalTriggerActionAfterSpeech = .none
        externalTriggerDelayAfterSpeech = 0
        waitsForNeonSpotlightAfterSpeech = false
        waitsForUserInactivityAfterSpeech = false
    }

    private func playRecordingFailureCue() {
        guard recordingCueSoundsEnabled else {
            return
        }

        recordingFailureCueSound
            .resolvedSound(stopSound: recordingStopCueSound)
            .play()
    }

    func ensureFocuSeeRecording() {
        Task { @MainActor [weak self] in
            _ = await self?.performExternalTriggerAction(.ensureRecording, reportsSuccess: true)
        }
    }

    func ensureFocuSeePaused() {
        Task { @MainActor [weak self] in
            _ = await self?.performExternalTriggerAction(.ensurePaused, reportsSuccess: true)
        }
    }

    private func performExternalTriggerAction(
        _ action: ExternalTriggerAction,
        reportsSuccess: Bool = false
    ) async -> Bool {
        switch action {
        case .none:
            return true
        case .toggle:
            return triggerRecordingShortcutIfPossible()
        case .ensureRecording:
            return await ensureFocuSeeState(.recording, reportsSuccess: reportsSuccess)
        case .ensurePaused:
            return await ensureFocuSeeState(.paused, reportsSuccess: reportsSuccess)
        }
    }

    private func ensureFocuSeeState(
        _ targetState: FocuSeeRecordingState,
        reportsSuccess: Bool
    ) async -> Bool {
        refreshShortcutTriggerAccessibilityStatus()
        guard isShortcutTriggerAccessibilityTrusted else {
            statusMessage = "Accessibility permission is required to inspect FocuSee."
            return false
        }

        let currentState = focuSeeAccessibilityService.recordingState()
        if currentState == targetState {
            if reportsSuccess {
                statusMessage = targetState == .recording
                    ? "FocuSee is already recording."
                    : "FocuSee is already paused."
            }
            return true
        }

        let oppositeState: FocuSeeRecordingState = targetState == .recording ? .paused : .recording
        guard currentState == oppositeState else {
            switch currentState {
            case .notRunning:
                statusMessage = "FocuSee is not open."
            case .notRecording:
                statusMessage = "FocuSee does not have an active recording."
            case .unknown:
                statusMessage = "Could not determine whether FocuSee is recording or paused."
            case .recording, .paused:
                statusMessage = "Could not safely change FocuSee's recording state."
            }
            return false
        }

        guard triggerRecordingShortcutIfPossible() else {
            return false
        }

        if reportsSuccess {
            statusMessage = targetState == .recording
                ? "Resuming FocuSee recording…"
                : "Pausing FocuSee recording…"
        }
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else {
            return false
        }

        let actualState = focuSeeAccessibilityService.recordingState()
        guard actualState == targetState else {
            statusMessage = "FocuSee did not change to the requested recording state."
            return false
        }

        if reportsSuccess {
            statusMessage = targetState == .recording
                ? "FocuSee is recording."
                : "FocuSee is paused."
        }
        return true
    }

    @discardableResult
    private func triggerRecordingShortcutIfPossible() -> Bool {
        guard let shortcut = recordingTriggerShortcut else {
            statusMessage = "Set the external FocuSee toggle shortcut first."
            return false
        }

        refreshShortcutTriggerAccessibilityStatus()
        guard isShortcutTriggerAccessibilityTrusted else {
            statusMessage = "Accessibility permission is required to trigger the recording shortcut."
            return false
        }

        if !shortcutTriggerService.trigger(shortcut) {
            statusMessage = "Could not trigger the recording shortcut."
            return false
        }
        refreshShortcutTriggerAccessibilityStatus()
        return true
    }

    private static func storedRecordingTriggerShortcut(in defaults: UserDefaults) -> TriggerShortcut? {
        guard let data = defaults.data(forKey: recordingShortcutValueKey) else {
            return nil
        }

        return try? JSONDecoder().decode(TriggerShortcut.self, from: data)
    }

    private func bindSpeechState() {
        ttsManager.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.speechState = state
                self?.persistExternalSpeechState(state)
                if state != .speaking {
                    self?.statusMessage = state.label
                }
                if state == .idle {
                    self?.applyPendingChapterReloadIfNeeded()
                }
                self?.refreshPresenterOverlayVisibility()
            }
            .store(in: &cancellables)

        ttsManager.$resolvedVoiceDescription
            .receive(on: DispatchQueue.main)
            .sink { [weak self] description in
                self?.outputVoiceDescription = description
            }
            .store(in: &cancellables)

        ttsManager.$resolvedVoiceNote
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                self?.outputVoiceNote = note
            }
            .store(in: &cancellables)

        ttsManager.$completedUtteranceCount
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleCompletedSpeech()
            }
            .store(in: &cancellables)
    }

    private func persistExternalSpeechState(_ state: SpeechState) {
        let stateValue: String
        switch state {
        case .idle:
            stateValue = "idle"
        case .speaking:
            stateValue = "speaking"
        case .paused:
            stateValue = "paused"
        case .stopping:
            stateValue = "stopping"
        }

        let payload: [String: Any] = [
            "state": stateValue,
            "updatedAt": Date().timeIntervalSince1970
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            return
        }

        try? data.write(
            to: URL(fileURLWithPath: Self.externalTTSStatePath),
            options: .atomic
        )
    }

    private func handleCompletedSpeech() {
        if isSceneManagerNarrationQueuePlaying {
            playNextSceneManagerNarration()
            return
        }
        performExternalTriggerActionAfterCompletedSpeechIfNeeded()
    }

    private func performExternalTriggerActionAfterCompletedSpeechIfNeeded() {
        guard let sequenceID = activeReadSequenceID else {
            return
        }

        let action = externalTriggerActionAfterSpeech
        let delay = externalTriggerDelayAfterSpeech
        let waitsForNeonSpotlight = waitsForNeonSpotlightAfterSpeech
        let waitsForUserInactivity = waitsForUserInactivityAfterSpeech
        externalTriggerActionAfterSpeech = .none
        externalTriggerDelayAfterSpeech = 0
        waitsForNeonSpotlightAfterSpeech = false
        waitsForUserInactivityAfterSpeech = false

        pendingReadTask = Task { @MainActor [weak self] in
            if action != .none, delay > 0 {
                self?.statusMessage = "Finishing recording in \(Self.formattedDelay(delay)) seconds…"
                try? await Task.sleep(for: .seconds(delay))
            }

            guard !Task.isCancelled,
                  let self,
                  self.activeReadSequenceID == sequenceID else {
                return
            }

            if action == .ensurePaused, waitsForNeonSpotlight {
                self.statusMessage = "Waiting for Neon Spotlight animation…"
                let waitResult = await self.neonSpotlightStatusService
                    .waitUntilIdle()
                guard !Task.isCancelled,
                      self.activeReadSequenceID == sequenceID else {
                    return
                }
                switch waitResult {
                case .alreadyIdle, .notRunning:
                    break
                case .completed:
                    self.statusMessage = "Neon Spotlight animation completed. Pausing recording…"
                case .appTerminated:
                    self.statusMessage = "Neon Spotlight closed. Pausing recording…"
                case .responseTimedOut:
                    self.statusMessage = "Neon Spotlight did not respond. Pausing recording…"
                case .animationTimedOut:
                    self.statusMessage = "Neon Spotlight wait timed out. Pausing recording…"
                case .cancelled:
                    return
                }
            }

            if action == .ensurePaused, waitsForUserInactivity {
                self.statusMessage = "Waiting for mouse and keyboard to become idle…"
                let idleResult = await self.userActivityIdleService.waitUntilIdle(
                    idlePeriod: self.userActivityIdlePeriod,
                    maximumWait: self.userActivityMaximumWait
                )
                guard !Task.isCancelled,
                      self.activeReadSequenceID == sequenceID else {
                    return
                }
                switch idleResult {
                case .idle:
                    self.statusMessage = "Mouse and keyboard are idle. Pausing recording…"
                case .timedOut:
                    self.statusMessage = "Activity wait timed out. Pausing recording…"
                case .monitoringUnavailable:
                    self.statusMessage = "Could not monitor input activity. Pausing recording…"
                case .cancelled:
                    return
                }
            }

            let actionSucceeded = await self.performExternalTriggerAction(action)
            guard !Task.isCancelled, self.activeReadSequenceID == sequenceID else {
                return
            }

            if actionSucceeded, action == .ensurePaused, self.recordingCueSoundsEnabled {
                if self.recordingStopCueDelay > 0 {
                    try? await Task.sleep(for: .seconds(self.recordingStopCueDelay))
                }
                guard !Task.isCancelled, self.activeReadSequenceID == sequenceID else {
                    return
                }
                self.recordingStopCueSound.play()
            } else if !actionSucceeded, action != .none {
                self.playRecordingFailureCue()
            }

            self.pendingReadTask = nil
            self.activeReadSequenceID = nil
            if actionSucceeded {
                self.advanceScriptSceneAfterCompletedSpeech()
            }
        }
    }

    private func advanceScriptSceneAfterCompletedSpeech() {
        guard scriptModeEnabled, shouldAdvanceScriptSceneAfterSpeech else {
            return
        }

        shouldAdvanceScriptSceneAfterSpeech = false
        refreshScriptScenes()

        if canGoToNextScene {
            currentSceneIndex += 1
            statusMessage = "Ready for \(scriptSceneProgress)"
        } else {
            statusMessage = "Script finished."
        }
    }

    private func registerShortcutHandlers() {
        KeyboardShortcuts.onKeyUp(for: .readClipboard) { [weak self] in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.readNow(
                    actionBefore: self.readShortcutOneActionBefore,
                    actionAfter: self.readShortcutOneActionAfter,
                    delayBefore: self.readShortcutOneDelayBefore,
                    delayAfter: self.readShortcutOneDelayAfter,
                    waitsForNeonSpotlight: self.readShortcutOneWaitsForNeonSpotlight,
                    waitsForUserInactivity: self.readShortcutOneWaitsForUserInactivity,
                    speedMultiplier: self.readShortcutOneSpeedMultiplier
                )
            }
        }

        KeyboardShortcuts.onKeyUp(for: .readCurrentInputSecondary) { [weak self] in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.readNow(
                    actionBefore: self.readShortcutTwoActionBefore,
                    actionAfter: self.readShortcutTwoActionAfter,
                    delayBefore: self.readShortcutTwoDelayBefore,
                    delayAfter: self.readShortcutTwoDelayAfter,
                    waitsForNeonSpotlight: self.readShortcutTwoWaitsForNeonSpotlight,
                    waitsForUserInactivity: self.readShortcutTwoWaitsForUserInactivity,
                    speedMultiplier: self.readShortcutTwoSpeedMultiplier
                )
            }
        }

        KeyboardShortcuts.onKeyUp(for: .readClipboardAlways) { [weak self] in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.readClipboardAlways(
                    actionBefore: self.readClipboardAlwaysActionBefore,
                    actionAfter: self.readClipboardAlwaysActionAfter,
                    delayBefore: self.readClipboardAlwaysDelayBefore,
                    delayAfter: self.readClipboardAlwaysDelayAfter,
                    waitsForNeonSpotlight: self.readClipboardAlwaysWaitsForNeonSpotlight,
                    waitsForUserInactivity: self.readClipboardAlwaysWaitsForUserInactivity,
                    speedMultiplier: self.readClipboardAlwaysSpeedMultiplier
                )
            }
        }

        KeyboardShortcuts.onKeyUp(for: .readClipboardAlwaysSecondary) { [weak self] in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.readClipboardAlways(
                    actionBefore: self.readClipboardAlwaysTwoActionBefore,
                    actionAfter: self.readClipboardAlwaysTwoActionAfter,
                    delayBefore: self.readClipboardAlwaysTwoDelayBefore,
                    delayAfter: self.readClipboardAlwaysTwoDelayAfter,
                    waitsForNeonSpotlight: self.readClipboardAlwaysTwoWaitsForNeonSpotlight,
                    waitsForUserInactivity: self.readClipboardAlwaysTwoWaitsForUserInactivity,
                    speedMultiplier: self.readClipboardAlwaysTwoSpeedMultiplier
                )
            }
        }

        KeyboardShortcuts.onKeyUp(for: .readClipboardAlwaysTertiary) { [weak self] in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.readClipboardAlways(
                    actionBefore: self.readClipboardAlwaysThreeActionBefore,
                    actionAfter: self.readClipboardAlwaysThreeActionAfter,
                    delayBefore: self.readClipboardAlwaysThreeDelayBefore,
                    delayAfter: self.readClipboardAlwaysThreeDelayAfter,
                    waitsForNeonSpotlight: self.readClipboardAlwaysThreeWaitsForNeonSpotlight,
                    waitsForUserInactivity: self.readClipboardAlwaysThreeWaitsForUserInactivity,
                    speedMultiplier: self.readClipboardAlwaysThreeSpeedMultiplier
                )
            }
        }

        KeyboardShortcuts.onKeyUp(for: .stopReading) { [weak self] in
            Task { @MainActor in
                self?.stopReading()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .pauseResumeReading) { [weak self] in
            Task { @MainActor in
                self?.togglePauseResume()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .replayScriptScene) { [weak self] in
            Task { @MainActor in
                self?.replayCurrentScriptScene()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .replayOnScreenOnly) { [weak self] in
            Task { @MainActor in
                self?.replayCurrentOnScreenOnly()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .previousScriptScene) { [weak self] in
            Task { @MainActor in
                self?.goToPreviousScene()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .nextScriptScene) { [weak self] in
            Task { @MainActor in
                self?.goToNextScene()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .restartScript) { [weak self] in
            Task { @MainActor in
                self?.restartScript()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .togglePresenterOverlay) { [weak self] in
            Task { @MainActor in
                self?.togglePresenterOverlay()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .editCurrentScene) { [weak self] in
            Task { @MainActor in
                self?.toggleCurrentSceneEditor()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .ensureFocuSeeRecording) { [weak self] in
            Task { @MainActor in
                self?.ensureFocuSeeRecording()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .ensureFocuSeePaused) { [weak self] in
            Task { @MainActor in
                self?.ensureFocuSeePaused()
            }
        }

    }

    private func persistExternalTriggerAction(
        _ action: ExternalTriggerAction,
        actionKey: String,
        legacyBoolKey: String
    ) {
        defaults.set(action.rawValue, forKey: actionKey)
        defaults.set(action != .none, forKey: legacyBoolKey)
    }

    private static func storedExternalTriggerAction(
        in defaults: UserDefaults,
        actionKey: String,
        legacyBoolKey: String,
        legacyDefaultValue: Bool = false
    ) -> ExternalTriggerAction {
        if let rawValue = defaults.string(forKey: actionKey),
           let action = ExternalTriggerAction(rawValue: rawValue) {
            return action
        }

        return storedBool(
            in: defaults,
            forKey: legacyBoolKey,
            defaultValue: legacyDefaultValue
        ) ? .toggle : .none
    }

    private func persistTriggerDelay(_ delay: Double, key: String) {
        defaults.set(Self.clampTriggerDelay(delay), forKey: key)
    }

    private static func storedTriggerDelay(in defaults: UserDefaults, forKey key: String) -> Double {
        clampTriggerDelay(storedDouble(in: defaults, forKey: key, defaultValue: 0))
    }

    static func clampTriggerDelay(_ value: Double) -> Double {
        clamp(value, min: minTriggerDelay, max: maxTriggerDelay)
    }

    static func clampRecordingStartCueDelay(_ value: Double) -> Double {
        clamp(value, min: minRecordingStartCueDelay, max: maxRecordingStartCueDelay)
    }

    static func clampRecordingStopCueDelay(_ value: Double) -> Double {
        clamp(value, min: minRecordingStopCueDelay, max: maxRecordingStopCueDelay)
    }

    private static func formattedDelay(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func storedDouble(in defaults: UserDefaults, forKey key: String, defaultValue: Double) -> Double {
        guard defaults.object(forKey: key) != nil else {
            return defaultValue
        }

        return defaults.double(forKey: key)
    }

    private static func storedBool(in defaults: UserDefaults, forKey key: String, defaultValue: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else {
            return defaultValue
        }

        return defaults.bool(forKey: key)
    }

    private static func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        min(max(value, minValue), maxValue)
    }
}
