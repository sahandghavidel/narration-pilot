@preconcurrency import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let recordGuidedManually = Self("recordGuidedManually",
        default: KeyboardShortcuts.Shortcut(.m, modifiers: [.command, .shift]))

    static let guidedReplayNarration = Self("guidedReplayNarration", default: .init(.n, modifiers: [.command, .shift]))
    static let guidedImproveWording = Self("guidedImproveWording", default: .init(.e, modifiers: [.command, .shift]))
    static let guidedReplayVoice = Self("guidedReplayVoice", default: .init(.v, modifiers: [.command, .shift]))
    static let guidedStartPractice = Self("guidedStartPractice", default: .init(.p, modifiers: [.command, .shift]))
    static let guidedReplayPractice = Self("guidedReplayPractice", default: .init(.l, modifiers: [.command, .shift]))
    static let guidedImprovePractice = Self("guidedImprovePractice", default: .init(.i, modifiers: [.command, .shift]))
    static let guidedAgentRecord = Self("guidedAgentRecord", default: .init(.r, modifiers: [.command, .shift]))
    static let recordApprovedClipboardAudio = Self("recordApprovedClipboardAudio")

    static let approveClonedClipboardAudio = Self(
        "approveClonedClipboardAudio",
        default: KeyboardShortcuts.Shortcut(.a, modifiers: [.command, .shift])
    )

    static let regenerateClonedClipboardAudio = Self(
        "regenerateClonedClipboardAudio",
        default: KeyboardShortcuts.Shortcut(.g, modifiers: [.command, .shift])
    )

    static let generateClonedClipboardAudio = Self(
        "generateClonedClipboardAudio",
        default: KeyboardShortcuts.Shortcut(.t, modifiers: [.command, .shift])
    )

    static let readClipboard = Self(
        "readClipboard",
        default: KeyboardShortcuts.Shortcut(.r, modifiers: [.command, .option])
    )

    static let readCurrentInputSecondary = Self(
        "readCurrentInputSecondary",
        default: KeyboardShortcuts.Shortcut(.r, modifiers: [.command, .option, .shift])
    )

    static let readClipboardAlways = Self(
        "readClipboardAlways",
        default: KeyboardShortcuts.Shortcut(.c, modifiers: [.command, .option, .shift])
    )

    static let readClipboardAlwaysSecondary = Self(
        "readClipboardAlwaysSecondary",
        default: KeyboardShortcuts.Shortcut(.v, modifiers: [.command, .option, .shift])
    )

    static let readClipboardAlwaysTertiary = Self(
        "readClipboardAlwaysTertiary",
        default: KeyboardShortcuts.Shortcut(.b, modifiers: [.command, .option, .shift])
    )

    static let stopReading = Self(
        "stopReading",
        default: KeyboardShortcuts.Shortcut(.s, modifiers: [.command, .option])
    )

    static let pauseResumeReading = Self(
        "pauseResumeReading",
        default: KeyboardShortcuts.Shortcut(.p, modifiers: [.command, .option])
    )

    static let replayScriptScene = Self(
        "replayScriptScene",
        default: KeyboardShortcuts.Shortcut(.upArrow, modifiers: [.command, .option])
    )

    static let replayOnScreenOnly = Self(
        "replayOnScreenOnly",
        default: KeyboardShortcuts.Shortcut(.upArrow, modifiers: [.command, .option, .shift])
    )

    static let replayCodeOnly = Self("replayCodeOnly")

    static let previousScriptScene = Self(
        "previousScriptScene",
        default: KeyboardShortcuts.Shortcut(.leftArrow, modifiers: [.command, .option])
    )

    static let nextScriptScene = Self(
        "nextScriptScene",
        default: KeyboardShortcuts.Shortcut(.rightArrow, modifiers: [.command, .option])
    )

    static let restartScript = Self(
        "restartScript",
        default: KeyboardShortcuts.Shortcut(.downArrow, modifiers: [.command, .option])
    )

    static let togglePresenterOverlay = Self(
        "togglePresenterOverlay",
        default: KeyboardShortcuts.Shortcut(.o, modifiers: [.command, .option])
    )

    static let editCurrentScene = Self(
        "editCurrentScene",
        default: KeyboardShortcuts.Shortcut(.e, modifiers: [.command, .option])
    )

    static let openFocusAndPlaySceneManager = Self("openFocusAndPlaySceneManager")

    static let ensureFocuSeeRecording = Self("ensureFocuSeeRecording")

    static let copyCurrentSceneForAgent = Self("copyCurrentSceneForAgent")

    static let ensureFocuSeePaused = Self("ensureFocuSeePaused")
}
