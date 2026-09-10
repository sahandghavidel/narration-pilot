import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if AppModel.shared.scriptInputFormat == .baserow, AppModel.shared.hasBaserowConfiguration {
            AppModel.shared.restoreBaserowIfAvailable()
        } else if AppModel.shared.scriptInputFormat == .json, AppModel.shared.hasNotionConfiguration {
            AppModel.shared.restoreNotionIfAvailable()
        } else {
            AppModel.shared.restoreLastChapterJSONIfAvailable()
        }
        AppModel.shared.checkAccessibilityPermissionAtLaunch()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppModel.shared.recheckAccessibilityPermission()
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard let filename = filenames.first else {
            sender.reply(toOpenOrPrint: .failure)
            return
        }

        AppModel.shared.importChapterJSON(
            from: URL(fileURLWithPath: filename),
            confirmsReplacement: true
        )
        sender.activate(ignoringOtherApps: true)
        sender.reply(toOpenOrPrint: .success)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let requestURL = urls.first,
              requestURL.scheme == "narrationpilot",
              requestURL.host == "import",
              let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false),
              let path = components.queryItems?.first(where: { $0.name == "path" })?.value,
              !path.isEmpty else {
            return
        }

        AppModel.shared.importChapterJSON(
            from: URL(fileURLWithPath: path),
            confirmsReplacement: true
        )
        application.activate(ignoringOtherApps: true)
    }
}
