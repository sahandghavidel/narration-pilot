@preconcurrency import KeyboardShortcuts

extension KeyboardShortcuts.Name {
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

    static let ensureFocuSeeRecording = Self("ensureFocuSeeRecording")

    static let ensureFocuSeePaused = Self("ensureFocuSeePaused")
}
