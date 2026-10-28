import AppKit
import ApplicationServices
import Foundation

enum FocuSeeRecordingState: Equatable {
    case notRunning
    case notRecording
    case recording
    case paused
    case unknown

    var allowsSceneReview: Bool {
        switch self {
        case .recording, .unknown: false
        case .paused, .notRunning, .notRecording: true
        }
    }
}

struct FocuSeeAccessibilityElementSnapshot: Equatable {
    let role: String
    let labels: [String]
    let isEnabled: Bool
}

struct FocuSeeAccessibilityService {
    static let bundleIdentifier = "com.imobie.FocuSee"

    func recordingState() -> FocuSeeRecordingState {
        guard let application = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.bundleIdentifier
        ).first else {
            return .notRunning
        }

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        let snapshots = accessibilitySnapshots(from: applicationElement)
        return Self.classify(isRunning: true, elements: snapshots)
    }

    static func classify(
        isRunning: Bool,
        elements: [FocuSeeAccessibilityElementSnapshot]
    ) -> FocuSeeRecordingState {
        guard isRunning else {
            return .notRunning
        }

        let actionableRoles = [kAXButtonRole as String, kAXMenuItemRole as String]
        let actionableElements = elements.filter {
            $0.isEnabled && actionableRoles.contains($0.role)
        }

        let hasPauseAction = actionableElements.contains { element in
            element.labels.contains { pauseActionLabels.contains(normalize($0)) }
        }
        let hasResumeAction = actionableElements.contains { element in
            element.labels.contains { resumeActionLabels.contains(normalize($0)) }
        }

        if hasPauseAction != hasResumeAction {
            return hasPauseAction ? .recording : .paused
        }

        let allLabels = elements.flatMap(\.labels).map(normalize)
        if allLabels.contains(where: pausedStatusLabels.contains) {
            return .paused
        }
        if allLabels.contains(where: recordingStatusLabels.contains) {
            return .recording
        }
        if allLabels.contains("please select the recording mode") {
            return .notRecording
        }
        let hasEditorWindow = elements.contains {
            $0.role == kAXWindowRole as String && $0.labels.contains { normalize($0) == "edit" }
        }
        let hasExportAction = actionableElements.contains {
            $0.labels.contains { normalize($0) == "export" }
        }
        if hasEditorWindow && hasExportAction {
            return .notRecording
        }

        let hasDisabledRecordingControl = elements.contains { element in
            guard !element.isEnabled, actionableRoles.contains(element.role) else {
                return false
            }
            return element.labels.contains { label in
                let normalized = normalize(label)
                return pauseActionLabels.contains(normalized) || resumeActionLabels.contains(normalized)
            }
        }

        return hasDisabledRecordingControl ? .notRecording : .unknown
    }

    private func accessibilitySnapshots(
        from root: AXUIElement
    ) -> [FocuSeeAccessibilityElementSnapshot] {
        var snapshots: [FocuSeeAccessibilityElementSnapshot] = []
        var queue: [(element: AXUIElement, depth: Int)] = [(root, 0)]
        var index = 0

        while index < queue.count, index < 1_500 {
            let current = queue[index]
            index += 1

            if let snapshot = snapshot(for: current.element) {
                snapshots.append(snapshot)
            }

            guard current.depth < 14 else {
                continue
            }

            for attribute in [kAXChildrenAttribute, kAXWindowsAttribute] {
                if let children = copyElements(attribute, from: current.element) {
                    queue.append(contentsOf: children.map { ($0, current.depth + 1) })
                }
            }

            if current.depth == 0,
               let menuBar = copyElement(kAXMenuBarAttribute, from: current.element) {
                queue.append((menuBar, current.depth + 1))
            }
        }

        return snapshots
    }

    private func snapshot(for element: AXUIElement) -> FocuSeeAccessibilityElementSnapshot? {
        guard let role = copyString(kAXRoleAttribute, from: element) else {
            return nil
        }

        let labels = [
            kAXTitleAttribute,
            kAXDescriptionAttribute,
            kAXHelpAttribute,
            kAXValueAttribute,
            kAXIdentifierAttribute
        ]
        .compactMap { copyString($0, from: element) }
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        let isEnabled = copyBool(kAXEnabledAttribute, from: element) ?? true
        return FocuSeeAccessibilityElementSnapshot(
            role: role,
            labels: labels,
            isEnabled: isEnabled
        )
    }

    private func copyValue(_ attribute: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private func copyString(_ attribute: String, from element: AXUIElement) -> String? {
        copyValue(attribute, from: element) as? String
    }

    private func copyBool(_ attribute: String, from element: AXUIElement) -> Bool? {
        copyValue(attribute, from: element) as? Bool
    }

    private func copyElements(_ attribute: String, from element: AXUIElement) -> [AXUIElement]? {
        copyValue(attribute, from: element) as? [AXUIElement]
    }

    private func copyElement(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        guard let value = copyValue(attribute, from: element),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func normalize(_ label: String) -> String {
        label
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private static let pauseActionLabels: Set<String> = [
        "pause",
        "pause recording"
    ]

    private static let resumeActionLabels: Set<String> = [
        "resume",
        "resume recording",
        "continue recording"
    ]

    private static let pausedStatusLabels: Set<String> = [
        "paused"
    ]

    private static let recordingStatusLabels: Set<String> = [
        "rec",
        "recording"
    ]
}
