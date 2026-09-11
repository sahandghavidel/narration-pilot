import SwiftUI

@main
struct NarrationPilotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel.shared

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
