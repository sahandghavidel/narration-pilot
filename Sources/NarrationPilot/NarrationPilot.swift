import SwiftUI
import Darwin

@main
struct NarrationPilotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel: AppModel

    init() {
        guard RuntimeReliability.shared.prepare(name: "Narration Pilot", identifier: "local.clipboardreadermac") else { Darwin.exit(0) }
        _appModel = StateObject(wrappedValue: AppModel.shared)
    }

    var body: some Scene {
        MenuBarExtra("Narration Pilot", systemImage: "text.bubble") {
            MenuBarView()
                .environmentObject(appModel)
                .onOpenURL { url in
                    appModel.handleExternalTTSURL(url)
                }
        }
        .menuBarExtraStyle(.window)
    }
}
