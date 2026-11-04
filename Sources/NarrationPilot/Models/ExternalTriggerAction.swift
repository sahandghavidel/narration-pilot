import Foundation

enum ExternalTriggerAction: String, CaseIterable, Identifiable, Codable, Sendable {
    case none
    case toggle
    case ensureRecording
    case ensurePaused

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:
            "Do nothing"
        case .toggle:
            "Toggle external shortcut"
        case .ensureRecording:
            "Ensure FocuSee is recording"
        case .ensurePaused:
            "Ensure FocuSee is paused"
        }
    }
}
