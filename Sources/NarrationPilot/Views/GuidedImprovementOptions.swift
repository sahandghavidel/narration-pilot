import SwiftUI

struct GuidedImprovementPreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var label: String
    var instruction: String

    static let wording = defaults(["Make it shorter", "Add a little detail", "Make it sound like me", "Make it clearer for beginners"])
    static let practice = defaults(["Make the actions faster", "Make the actions slower", "Match the narration better", "Show the result longer"])

    private static func defaults(_ labels: [String]) -> [Self] {
        labels.map { Self(label: $0, instruction: $0) }
    }
}

struct GuidedImprovementOptions: View {
    let action: GuidedAction
    let submit: (String) -> Void
    let close: () -> Void

    @AppStorage private var saved: Data
    @State private var page = Page.options
    @State private var draft = GuidedImprovementPreset(label: "", instruction: "")
    @State private var customInstruction = ""
    @State private var fromCustom = false
    @FocusState private var focus: Field?

    private enum Page { case options, custom, manage, edit }
    private enum Field { case label, instruction }

    init(action: GuidedAction, submit: @escaping (String) -> Void, close: @escaping () -> Void) {
        self.action = action
        self.submit = submit
        self.close = close
        let kind = action == .improveWording ? "wording" : "practice"
        _saved = AppStorage(wrappedValue: Data(), "NarrationPilot.improvementPresets.\(kind)")
    }

    private var presets: [GuidedImprovementPreset] {
        if let stored = try? JSONDecoder().decode([GuidedImprovementPreset].self, from: saved) { return stored }
        return action == .improveWording ? GuidedImprovementPreset.wording : GuidedImprovementPreset.practice
    }

    private func persist(_ items: [GuidedImprovementPreset]) {
        if let data = try? JSONEncoder().encode(items) { saved = data }
    }

    private func move(_ preset: GuidedImprovementPreset, by offset: Int) {
        var items = presets
        guard let index = items.firstIndex(where: { $0.id == preset.id }),
              items.indices.contains(index + offset) else { return }
        items.swapAt(index, index + offset)
        persist(items)
    }

    private func edit(_ preset: GuidedImprovementPreset, fromCustom: Bool = false) {
        draft = preset
        self.fromCustom = fromCustom
        page = .edit
    }

    private func savePreset() {
        var item = draft
        item.label = item.label.trimmingCharacters(in: .whitespacesAndNewlines)
        item.instruction = item.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.label.isEmpty, !item.instruction.isEmpty else { return }
        var items = presets
        if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = item }
        else { items.append(item) }
        persist(items)
        if fromCustom { customInstruction = item.instruction }
        page = fromCustom ? .custom : .manage
    }

    var body: some View {
        let items = presets
        VStack(alignment: .leading, spacing: 8) {
            switch page {
            case .options:
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], alignment: .leading) {
                    ForEach(items) { item in
                        Button(item.label) { submit(item.instruction) }.help(item.instruction)
                    }
                    Button("Give my own instruction…") { page = .custom }
                }
                Button("Manage options…") { page = .manage }
            case .custom:
                Text(action == .improveWording ? "What should change in the wording?" : "What should change in the practice?")
                    .font(.caption)
                instructionEditor($customInstruction, label: "Custom improvement instruction")
                    .task { await Task.yield(); focus = .instruction }
                HStack {
                    Button("Send instruction") { submit(customInstruction) }
                    Button("Save as preset…") {
                        edit(.init(label: "", instruction: customInstruction), fromCustom: true)
                    }
                }
                .disabled(customInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", action: close)
            case .manage:
                Text(action == .improveWording ? "Wording presets" : "Practice presets").font(.subheadline.bold())
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack {
                        Text(item.label)
                        Spacer()
                        Button("Edit") { edit(item) }.accessibilityLabel("Edit \(item.label)")
                        Button {
                            move(item, by: -1)
                        } label: { Image(systemName: "arrow.up") }
                        .accessibilityLabel("Move \(item.label) up").disabled(index == 0)
                        Button {
                            move(item, by: 1)
                        } label: { Image(systemName: "arrow.down") }
                        .accessibilityLabel("Move \(item.label) down").disabled(index + 1 == items.count)
                        Button {
                            persist(presets.filter { $0.id != item.id })
                        } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Delete \(item.label)")
                    }
                }
                HStack {
                    Button("Add preset…") { edit(.init(label: "", instruction: "")) }
                    Button("Done managing") { page = .options }
                }
            case .edit:
                Text("Button label").font(.caption)
                TextField("Button label", text: $draft.label)
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .label)
                    .task { await Task.yield(); focus = .label }
                Text("Agent instruction").font(.caption)
                instructionEditor($draft.instruction, label: "Agent instruction")
                HStack {
                    Button("Save preset", action: savePreset)
                        .disabled(draft.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                  draft.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Cancel") { page = fromCustom ? .custom : .manage }
                }
            }
        }
    }

    private func instructionEditor(_ text: Binding<String>, label: String) -> some View {
        TextEditor(text: text)
            .frame(height: 60)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(.secondary.opacity(0.3)))
            .focused($focus, equals: .instruction)
            .accessibilityLabel(label)
    }
}
