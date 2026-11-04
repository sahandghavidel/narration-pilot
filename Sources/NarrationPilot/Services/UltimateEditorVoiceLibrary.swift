import Combine
import Foundation

struct UltimateEditorVoice: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let provider: String
    let language: String
    let enabled: Bool

    var engineLabel: String {
        provider == "omnivoice-lora" ? "OmniVoice LoRA" : "OmniVoice"
    }
}

/// Voice selection only. Playback continues to use the existing macOS speech settings.
@MainActor
final class UltimateEditorVoiceLibrary: ObservableObject {
    static let selectionKey = "narrationPilot.ultimateEditor.selectedEnglishVoice"
    static let endpoint = URL(string: "http://localhost:9540/api/tts-audio-references")!

    @Published private(set) var voices: [UltimateEditorVoice] = []
    @Published private(set) var selectedVoice: UltimateEditorVoice?
    @Published private(set) var isLoading = false
    @Published private(set) var message = ""
    @Published private(set) var connectionFailed = false
    @Published private(set) var hasLoaded = false

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.selectionKey) {
            selectedVoice = try? JSONDecoder().decode(UltimateEditorVoice.self, from: data)
        }
    }

    var selectedID: String { selectedVoice?.id ?? "" }

    var selectionUnavailable: Bool {
        hasLoaded && selectedVoice != nil && !voices.contains { $0.id == selectedID }
    }

    func select(_ id: String) {
        if id.isEmpty {
            selectedVoice = nil
            defaults.removeObject(forKey: Self.selectionKey)
        } else if let voice = voices.first(where: { $0.id == id }) {
            save(voice)
        }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            var request = URLRequest(url: Self.endpoint)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else {
                throw URLError(.badServerResponse)
            }
            struct Library: Decodable { let entries: [UltimateEditorVoice] }
            let library = try JSONDecoder().decode(Library.self, from: data)
            var seen = Set<String>()
            voices = library.entries.filter {
                $0.enabled && !$0.id.isEmpty
                    && ($0.language.lowercased() == "en" || $0.language.lowercased().hasPrefix("en-"))
                    && ["omnivoice", "omnivoice-lora"].contains($0.provider)
                    && seen.insert($0.id).inserted
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            hasLoaded = true
            connectionFailed = false
            if let updated = voices.first(where: { $0.id == selectedID }) {
                save(updated)
            }
            message = voices.isEmpty ? "No enabled English voices found." : "Connected · \(voices.count) English voices"
        } catch {
            guard !Task.isCancelled else { return }
            connectionFailed = true
            message = "Could not load voices. Open Ultimate Video Editor at localhost:9540, then refresh. Your saved choice is kept."
        }
    }

    private func save(_ voice: UltimateEditorVoice) {
        guard let data = try? JSONEncoder().encode(voice) else { return }
        defaults.set(data, forKey: Self.selectionKey)
        selectedVoice = voice
    }
}
