import AppKit
import AppKit
import SwiftUI

struct JSONSceneManagerView: View {
    @EnvironmentObject private var appModel: AppModel
    let chapter: NarrationChapter
    let initialIndex: Int
    let close: () -> Void

    @State private var selectedIndex: Int
    @State private var workingChapter: NarrationChapter
    @State private var narration = ""
    @State private var onScreen = ""
    @State private var annotation = ""
    @State private var codeText = ""
    @State private var codeInstruction = ""
    @State private var activeField: EditableField?
    @FocusState private var focusedField: EditableField?
    @State private var previewFontSize = UserDefaults.standard.object(forKey: "NarrationPilot.jsonPreviewFontSize") as? Double ?? 14
    @State private var sortByNewestEdited = false

    private enum EditableField: Hashable { case narration, onScreen, code }

    init(chapter: NarrationChapter, selectedIndex: Int, close: @escaping () -> Void) {
        self.chapter = chapter
        self.initialIndex = min(max(selectedIndex, 0), max(chapter.scenes.count - 1, 0))
        self.close = close
        self._selectedIndex = State(initialValue: self.initialIndex)
        self._workingChapter = State(initialValue: chapter)
    }

    var body: some View {
        HStack(spacing: 0) {
            sceneList
                .frame(width: 260)
                .padding(.vertical, 14)
                .padding(.leading, 14)
                .padding(.trailing, 10)

            Divider()

            sceneDetails
                .padding(18)
        }
        .toolbar {
            ToolbarItemGroup {
                Button { changeFontSize(-1) } label: { Image(systemName: "minus") }
                Text("\(Int(previewFontSize)) pt").font(.caption)
                Button { changeFontSize(1) } label: { Image(systemName: "plus") }
            }
        }
        .frame(minWidth: 780, minHeight: 500)
        .onAppear {
            appModel.selectSceneForEditing(selectedIndex)
            loadDraft()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sceneEditorShouldClose)) { _ in
            if commitEdits() { close() }
        }
        .background(
            SceneArrowKeyMonitor { direction in
                navigate(direction)
            }
        )
    }

    /// Moves scene selection by arrow key. ⌘-modified arrows work even while typing.
    private func navigate(_ direction: SceneArrowKeyMonitor.Direction) {
        let order = displayedSceneIndices
        guard let position = order.firstIndex(of: selectedIndex) else { return }
        let next = position + (direction == .up ? -1 : 1)
        guard order.indices.contains(next) else { return }
        select(order[next])
    }

    private var sceneList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Chapter \(workingChapter.chapterNumber)")
                    .font(.headline)
                Spacer()
                if appModel.hasConnectedSceneSource {
                    Button {
                        sortByNewestEdited.toggle()
                    } label: {
                        Label(sortByNewestEdited ? "Newest" : "Order",
                              systemImage: sortByNewestEdited ? "clock.arrow.circlepath" : "list.number")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help(sortByNewestEdited ? "Sorted by last edited (newest first). Click to restore scene order." : "Sort by last edited (newest first)")
                }
            }

            Text(workingChapter.chapterTitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(displayedSceneIndices, id: \.self) { index in
                            let scene = workingChapter.scenes[index]
                            Button {
                                guard commitEdits() else { return }
                                selectedIndex = index
                                loadDraft()
                                activeField = nil
                                appModel.selectSceneForEditing(index)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 5) {
                                        Text("Scene \(scene.sceneNumber)")
                                            .font(.caption.bold())
                                        if sortByNewestEdited, let date = appModel.sceneLastEdited(forSceneID: scene.id) {
                                            Spacer()
                                            Text(date.formatted(.relative(presentation: .named)))
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    Text(scene.narration)
                                        .font(.caption2)
                                        .lineLimit(2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(index == selectedIndex ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
                                )
                            }
                            .buttonStyle(.plain)
                            .id(index)
                        }
                    }
                }
                .onAppear {
                    DispatchQueue.main.async {
                        proxy.scrollTo(selectedIndex, anchor: .top)
                    }
                }
            }

            Text("Scene \(selectedIndex + 1) of \(workingChapter.scenes.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Scene indices in sidebar display order: natural order, or newest-edited first when sorting is on.
    private var displayedSceneIndices: [Int] {
        let all = Array(workingChapter.scenes.indices)
        guard sortByNewestEdited else { return all }
        return all.sorted { lhs, rhs in
            let lID = workingChapter.scenes[lhs].id
            let rID = workingChapter.scenes[rhs].id
            let lDate = appModel.sceneLastEdited(forSceneID: lID) ?? .distantPast
            let rDate = appModel.sceneLastEdited(forSceneID: rID) ?? .distantPast
            if lDate != rDate { return lDate > rDate }
            return workingChapter.scenes[lhs].sceneNumber < workingChapter.scenes[rhs].sceneNumber
        }
    }

    private var sceneDetails: some View {
        let scene = workingChapter.scenes[selectedIndex]

        return VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    editableField("Narration", field: .narration, text: $narration)
                    editableField("On Screen", field: .onScreen, text: $onScreen)
                    onScreenLinks
                    if let code = scene.code {
                        codeSection(code)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            annotationField

            Text(appModel.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack {
                Button("Save Changes") { _ = saveChanges() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasUnsavedChanges)
                Spacer()
                Button("Previous") { select(max(selectedIndex - 1, 0)) }
                    .disabled(selectedIndex == 0)
                Button("Next") { select(min(selectedIndex + 1, workingChapter.scenes.count - 1)) }
                    .disabled(selectedIndex >= workingChapter.scenes.count - 1)
                Button("Done") { if commitEdits() { close() } }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .background(
            WindowOutsideEditorClickMonitor {
                if activeField != nil || hasUnsavedChanges {
                    _ = commitEdits()
                }
            }
        )
    }

    @ViewBuilder
    private var onScreenLinks: some View {
        let urls = OnScreenLinkExtractor.urls(in: onScreen)

        if !urls.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text(urls.count == 1 ? "LINK" : "LINKS")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                ForEach(urls, id: \.absoluteString) { url in
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "arrow.up.right.square")
                            Text(url.absoluteString)
                                .multilineTextAlignment(.leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.link)
                    .help("Open in default browser")
                }
            }
            .padding(.top, -12)
        }
    }

    private func editableField(_ label: String, field: EditableField, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: fieldIcon(field))
                    .foregroundStyle(fieldColor(field))
                Text(label.uppercased()).font(.caption.bold()).foregroundStyle(.secondary)
                if activeField == field {
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
            if activeField == field {
                TextEditor(text: text)
                    .font(fieldFont(field))
                    .foregroundStyle(fieldTextColor(field))
                    .lineSpacing(field == .narration ? 5 : 2)
                    .focused($focusedField, equals: field)
                    .frame(height: max(64, min(180, CGFloat(text.wrappedValue.count / 65 + 1) * 30)))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(fieldBackground(field)))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(fieldColor(field).opacity(0.8)))
            } else {
                Button {
                    guard commitEdits() else { return }
                    activeField = field
                    focusedField = field
                } label: {
                    Text(text.wrappedValue.isEmpty ? "None" : text.wrappedValue)
                        .font(fieldFont(field))
                        .foregroundStyle(fieldTextColor(field))
                        .lineSpacing(field == .narration ? 5 : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(fieldBackground(field))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var annotationField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "note.text").foregroundStyle(.orange)
                Text("ANNOTATION").font(.caption.bold()).foregroundStyle(.secondary)
            }
            TextEditor(text: $annotation)
                .font(.system(size: previewFontSize))
                .frame(height: max(120, min(240, CGFloat(annotation.count / 65 + 1) * 34)))
                .padding(5)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.yellow.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.yellow.opacity(0.5)))
        }
    }

    private func fieldIcon(_ field: EditableField) -> String {
        switch field {
        case .narration: "text.bubble"
        case .onScreen: "rectangle.on.rectangle"
        case .code: "chevron.left.forwardslash.chevron.right"
        }
    }

    private func fieldColor(_ field: EditableField) -> Color {
        switch field {
        case .narration: .secondary
        case .onScreen: .blue
        case .code: .purple
        }
    }

    private func fieldFont(_ field: EditableField) -> Font {
        switch field {
        case .narration: .system(size: previewFontSize + 4, weight: .semibold)
        case .onScreen: .system(size: previewFontSize + 2)
        case .code: .system(size: previewFontSize, design: .monospaced)
        }
    }

    private func fieldTextColor(_ field: EditableField) -> Color {
        Color.primary.opacity(0.88)
    }

    private func fieldBackground(_ field: EditableField) -> Color {
        switch field {
        case .narration: Color.orange.opacity(0.07)
        default: fieldColor(field).opacity(0.09)
        }
    }

    private func changeFontSize(_ amount: Double) {
        previewFontSize = min(max(previewFontSize + amount, 10), 28)
        UserDefaults.standard.set(previewFontSize, forKey: "NarrationPilot.jsonPreviewFontSize")
    }

    private func loadDraft() {
        let scene = workingChapter.scenes[selectedIndex]
        narration = scene.narration
        onScreen = scene.onScreen
        annotation = scene.annotation ?? ""
        codeText = scene.code?.text ?? ""
        codeInstruction = scene.code?.instruction ?? scene.code.map { "\($0.action.rawValue.capitalized) this code in \($0.targetFile)." } ?? ""
    }

    @discardableResult
    private func saveChanges() -> Bool {
        let old = workingChapter.scenes[selectedIndex]
        let updatedCode = old.code.map {
            NarrationCode(
                text: codeText,
                language: $0.language,
                targetFile: $0.targetFile,
                action: $0.action,
                instruction: codeInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        let updated = NarrationScene(
            id: old.id, sceneNumber: old.sceneNumber, narration: narration,
            onScreen: onScreen, code: updatedCode,
            annotation: annotation.isEmpty ? nil : annotation
        )
        var scenes = workingChapter.scenes
        scenes[selectedIndex] = updated
        let updatedChapter = NarrationChapter(
            schemaVersion: workingChapter.schemaVersion, chapterNumber: workingChapter.chapterNumber,
            chapterTitle: workingChapter.chapterTitle, scenes: scenes
        )
        do {
            try NarrationChapterLoader.validate(updatedChapter)
            let data = try JSONEncoder.narrationPilot.encode(updatedChapter)
            appModel.saveEditedChapterJSON(String(data: data, encoding: .utf8) ?? "")
            workingChapter = updatedChapter
            activeField = nil
            focusedField = nil
            return true
        } catch {
            appModel.statusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    private func commitEdits() -> Bool {
        guard hasUnsavedChanges else {
            activeField = nil
            focusedField = nil
            return true
        }
        return saveChanges()
    }

    private var hasUnsavedChanges: Bool {
        let scene = workingChapter.scenes[selectedIndex]
        return narration != scene.narration ||
            onScreen != scene.onScreen ||
            annotation != (scene.annotation ?? "") ||
            codeText != (scene.code?.text ?? "") ||
            codeInstruction != (scene.code?.instruction ?? scene.code.map { "\($0.action.rawValue.capitalized) this code in \($0.targetFile)." } ?? "")
    }

    private func codeSection(_ code: NarrationCode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(code.language.uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(languageColor(code.language))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(languageColor(code.language).opacity(0.16)))
                Text("→ \(code.targetFile)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(activeField == .code ? "Done Editing" : "Edit Code") {
                    if activeField == .code {
                        _ = commitEdits()
                    } else {
                        guard commitEdits() else { return }
                        activeField = .code
                    }
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(codeText, forType: .string)
                } label: {
                    Label("Copy Code", systemImage: "doc.on.doc")
                }
            }

            if activeField == .code {
                TextField("Specific code instruction", text: $codeInstruction)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: previewFontSize + 1, weight: .medium))
            } else {
                Text(codeInstruction)
                    .font(.system(size: previewFontSize + 1, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            SyntaxHighlightedCodeEditor(
                text: $codeText,
                language: code.language,
                isEditable: activeField == .code
            )
            .frame(minHeight: activeField == .code ? 190 : 110, maxHeight: activeField == .code ? 300 : 180)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(activeField == .code ? languageColor(code.language) : Color.secondary.opacity(0.25), lineWidth: activeField == .code ? 1.5 : 1)
            )
        }
    }

    private func languageColor(_ language: String) -> Color {
        let value = language.lowercased()
        if value.contains("html") { return .blue }
        if value.contains("css") { return .orange }
        if value.contains("javascript") || value == "js" { return .yellow }
        return .purple
    }

    private func select(_ index: Int) {
        guard commitEdits() else { return }
        selectedIndex = index
        loadDraft()
        activeField = nil
        focusedField = nil
        appModel.selectSceneForEditing(index)
        // Resign first responder so keyboard focus leaves any text view (e.g. annotation).
        if let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && $0 is NSPanel }) {
            window.makeFirstResponder(nil)
        }
    }
}

/// Arrow-key navigation between scenes.
/// Plain ↑/↓ only fire when no text field has focus; ⌘↑/⌘↓ always navigate.
private struct SceneArrowKeyMonitor: NSViewRepresentable {
    enum Direction { case up, down }
    let onArrow: (Direction) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onArrow: onArrow)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.window = view.window
            context.coordinator.start()
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.onArrow = onArrow
        context.coordinator.window = view.window
        context.coordinator.start()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

        /// Only ever touched from the main thread (event monitors + view lifecycle).
        final class Coordinator: @unchecked Sendable {
        weak var window: NSWindow?
        var onArrow: (Direction) -> Void
        private var monitor: Any?

        init(onArrow: @escaping (Direction) -> Void) {
            self.onArrow = onArrow
        }

        func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      let key = self.direction(for: event.keyCode),
                      self.window?.isVisible == true else { return event }

                // Only act on this panel's events (or when our window is key).
                let isOurWindow = event.window === self.window || NSApp.keyWindow === self.window
                guard isOurWindow else { return event }

                let commandHeld = event.modifierFlags.contains(.command)

                if commandHeld {
                    // ⌘↑/⌘↓ always navigate, even while typing.
                    DispatchQueue.main.async { self.onArrow(key) }
                    return nil
                }

                // Plain arrows only navigate when no text input has focus.
                if self.isTextInputFocused { return event }
                DispatchQueue.main.async { self.onArrow(key) }
                return nil
            }
        }

        private func direction(for keyCode: UInt16) -> Direction? {
            switch keyCode {
            case 126: .up
            case 125: .down
            default: nil
            }
        }

        private var isTextInputFocused: Bool {
            guard let responder = window?.firstResponder else { return false }
            if responder is NSTextView { return true } // TextEditor / NSTextField field editor
            if let field = responder as? NSTextField, field.isEditable { return true }
            return false
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { stop() }
    }
}

private struct WindowOutsideEditorClickMonitor: NSViewRepresentable {
    let onOutsideClick: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOutsideClick: onOutsideClick)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.window = view.window
            context.coordinator.start()
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.onOutsideClick = onOutsideClick
        context.coordinator.window = view.window
        context.coordinator.start()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        weak var window: NSWindow?
        var onOutsideClick: () -> Void
        private var monitor: Any?

        init(onOutsideClick: @escaping () -> Void) {
            self.onOutsideClick = onOutsideClick
        }

        func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                let hitView = self.window?.contentView?.hitTest(event.locationInWindow)
                if hitView is NSTextView { return event }
                self.onOutsideClick()
                return event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { stop() }
    }
}
