import AppKit
import SwiftUI

extension Notification.Name {
    static let sceneEditorShouldClose = Notification.Name("NarrationPilot.sceneEditorShouldClose")
}

@MainActor
final class SceneEditorController: NSObject, NSWindowDelegate {
    private weak var appModel: AppModel?
    private var panel: NSPanel?
    private var isFinishingClose = false
    private let jsonWindowSizeKey = "NarrationPilot.jsonManagerWindowFrameSize.v2"

    init(appModel: AppModel) {
        self.appModel = appModel
        super.init()
    }

    var isVisible: Bool { panel?.isVisible == true }

    func show(activatesApp: Bool = true) {
        guard let appModel else {
            return
        }

        if let panel, panel.isVisible {
            present(panel, activatesApp: activatesApp)
            return
        }

        let panel: NSPanel
        if let chapter = appModel.loadedChapter, appModel.scriptInputFormat.usesStructuredScenes {
            let selectedIndex = min(appModel.currentSceneIndexForEditor, max(chapter.scenes.count - 1, 0))
            panel = makeJSONPanel(appModel: appModel, chapter: chapter, selectedIndex: selectedIndex)
        } else {
            let scenes = appModel.allSceneTexts.isEmpty ? [""] : appModel.allSceneTexts
            let selectedIndex = min(appModel.currentSceneIndexForEditor, max(scenes.count - 1, 0))
            panel = makeTextPanel(appModel: appModel, scenes: scenes, selectedIndex: selectedIndex)
        }
        self.panel = panel
        panel.center()
        present(panel, activatesApp: activatesApp)
    }

    private func present(_ panel: NSPanel, activatesApp: Bool) {
        if activatesApp {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    func toggle() {
        if let panel, panel.isVisible {
            requestSaveAndClose()
        } else {
            show()
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !isFinishingClose else {
            return true
        }

        requestSaveAndClose()
        return false
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === panel,
              window.title == "JSON Scene Manager",
              !isFinishingClose else {
            return
        }
        requestSaveAndClose()
    }

    private func requestSaveAndClose() {
        NotificationCenter.default.post(name: .sceneEditorShouldClose, object: nil)
    }

    private func finishClose() {
        guard let panel else {
            return
        }

        isFinishingClose = true
        if panel.title == "JSON Scene Manager" {
            UserDefaults.standard.set(NSStringFromSize(panel.frame.size), forKey: jsonWindowSizeKey)
        }
        panel.close()
        isFinishingClose = false
        self.panel = nil
    }

    private func makeTextPanel(appModel: AppModel, scenes: [String], selectedIndex: Int) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.contentView = NSHostingView(
            rootView: CurrentSceneEditorView(scenes: scenes, selectedIndex: selectedIndex) { [weak self] in
                self?.finishClose()
            }
            .environmentObject(appModel)
        )
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.minSize = NSSize(width: 720, height: 420)
        panel.sharingType = .none
        panel.title = "Scene Manager"

        return panel
    }

    private func makeJSONPanel(appModel: AppModel, chapter: NarrationChapter, selectedIndex: Int) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.contentView = NSHostingView(
            rootView: JSONSceneManagerView(
                chapter: chapter,
                selectedIndex: selectedIndex
            ) { [weak self] in
                self?.finishClose()
            }
            .environmentObject(appModel)
        )
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.minSize = NSSize(width: 780, height: 500)
        panel.sharingType = .none
        panel.title = "JSON Scene Manager"

        if let savedValue = UserDefaults.standard.string(forKey: jsonWindowSizeKey) {
            let savedSize = NSSizeFromString(savedValue)
            if savedSize.width >= panel.minSize.width, savedSize.height >= panel.minSize.height {
                panel.setFrame(
                    NSRect(origin: panel.frame.origin, size: savedSize),
                    display: false
                )
            }
        }

        return panel
    }
}
