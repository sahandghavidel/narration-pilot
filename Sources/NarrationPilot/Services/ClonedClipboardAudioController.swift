import AppKit
import AVFoundation
import Combine
import Foundation

struct ClipboardAudioTake: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let clipboardText: String
    let spokenText: String
    let voice: UltimateEditorVoice
    let duration: TimeInterval
    let generationResponse: String

    var label: String {
        "\(createdAt.formatted(date: .abbreviated, time: .standard)) · \(spokenText.prefix(45))"
    }
}

@MainActor
final class ClonedClipboardAudioController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    nonisolated static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/local.clipboardreadermac/ClonedClipboardAudio", isDirectory: true)

    @Published private(set) var takes: [ClipboardAudioTake] = []
    @Published private(set) var selectedID: UUID?
    @Published private(set) var isGenerating = false
    @Published private(set) var isPreviewing = false
    @Published private(set) var message = "Copy one scene’s narration, then generate a cloned voice preview."
    var macOSSpeechIsIdle: () -> Bool = { true }
    var recordingAllowsPreview: () async -> Bool = {
        await Task.detached(priority: .utility) {
            FocuSeeAccessibilityService().recordingState().allowsSceneReview
        }.value
    }

    private let directory: URL
    private let defaults: UserDefaults
    private let client: ClonedClipboardAudioClient
    private var player: AVAudioPlayer?
    private var previewTask: Task<Void, Never>?
    private var previewRevision = UUID()
    private static let selectedKey = "narrationPilot.clonedClipboard.selectedTake"

    init(directory: URL = ClonedClipboardAudioController.directory,
         defaults: UserDefaults = .standard, client: ClonedClipboardAudioClient = .init()) {
        self.directory = directory
        self.defaults = defaults
        self.client = client
        super.init()
        let folders = (try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        takes = folders.compactMap { folder in
            guard let folderID = UUID(uuidString: folder.lastPathComponent),
                  let data = try? Data(contentsOf: folder.appendingPathComponent("metadata.json")),
                  let take = try? JSONDecoder().decode(ClipboardAudioTake.self, from: data),
                  take.id == folderID,
                  FileManager.default.fileExists(atPath: folder.appendingPathComponent("audio.wav").path) else { return nil }
            return take
        }.sorted { $0.createdAt > $1.createdAt }
        let savedID = defaults.string(forKey: Self.selectedKey).flatMap(UUID.init(uuidString:))
        selectedID = takes.first(where: { $0.id == savedID })?.id ?? takes.first?.id
    }

    var selectedTake: ClipboardAudioTake? { takes.first { $0.id == selectedID } }

    func select(_ id: UUID) {
        guard takes.contains(where: { $0.id == id }) else { return }
        stopPreview()
        selectedID = id
        defaults.set(id.uuidString, forKey: Self.selectedKey)
    }

    func generateClipboard() {
        guard !isGenerating else { return }
        let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
        guard let voice = UltimateEditorVoiceLibrary(defaults: defaults).selectedVoice else {
            message = "Choose an English voice in Ultimate Video Editor voice first."
            return
        }
        // Set synchronously so repeated shortcut events cannot enqueue another request.
        isGenerating = true
        Task { await performGeneration(clipboard: clipboard, voiceID: voice.id) }
    }

    func generate(clipboard: String, voiceID: String) async {
        guard !isGenerating else { return }
        isGenerating = true
        await performGeneration(clipboard: clipboard, voiceID: voiceID)
    }

    private func performGeneration(clipboard: String, voiceID: String) async {
        defer { isGenerating = false }
        let text = SpokenTextSanitizer.preparingForSpeech(clipboard, includesBracketedDirections: false)
        guard !text.isEmpty else { message = "Copy some narration text first."; return }
        guard text.count <= 12000 else { message = "Copy one scene at a time (up to 12,000 characters)."; return }
        guard macOSSpeechIsIdle() else { message = "Wait for macOS speech to finish before generating a cloned preview."; return }
        guard await recordingAllowsPreview() else {
            message = "Pause FocuSee before generating a preview. Its recording state must be known."
            return
        }
        stopPreview()
        message = "Generating cloned clipboard audio…"
        do {
            let id = UUID()
            let generated = try await client.generate(text: text, voiceID: voiceID, requestID: id)
            message = "Saving cloned clipboard audio…"
            let take = try save(generated, id: id, clipboard: clipboard, text: text)
            takes.insert(take, at: 0)
            select(take.id)
            message = "Saved new audio version."
            await previewSelected()
        } catch {
            message = "Cloned voice: \(error.localizedDescription) Previous versions are kept."
        }
    }

    private func save(_ generated: GeneratedClipboardAudio, id: UUID, clipboard: String, text: String) throws -> ClipboardAudioTake {
        let validation = try AVAudioPlayer(data: generated.audio)
        guard validation.duration.isFinite, validation.duration > 0 else {
            throw NSError(domain: "ClonedClipboardAudio", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Generated audio has no playable duration."])
        }
        let take = ClipboardAudioTake(id: id, createdAt: Date(), clipboardText: clipboard, spokenText: text,
            voice: generated.voice, duration: validation.duration, generationResponse: generated.responseJSON)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let staging = directory.appendingPathComponent(".\(id.uuidString).pending", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: staging) }
        try generated.audio.write(to: staging.appendingPathComponent("audio.wav"), options: .atomic)
        try JSONEncoder().encode(take).write(to: staging.appendingPathComponent("metadata.json"), options: .atomic)
        try FileManager.default.moveItem(at: staging, to: directory.appendingPathComponent(id.uuidString, isDirectory: true))
        return take
    }

    func previewSelected() async {
        guard let take = selectedTake else { return }
        stopPreview()
        let revision = previewRevision
        let recordingAllowed = await recordingAllowsPreview()
        guard revision == previewRevision, selectedID == take.id else { return }
        guard macOSSpeechIsIdle(), recordingAllowed else {
            message = "Audio is saved. Preview when macOS speech is idle and FocuSee is paused."
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: audioURL(for: take))
            player.delegate = self
            guard player.prepareToPlay(), player.play() else {
                throw NSError(domain: "ClonedClipboardAudio", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "The saved audio could not start playing."])
            }
            self.player = player
            isPreviewing = true
            message = "Previewing cloned voice · \(take.duration.formatted(.number.precision(.fractionLength(1)))) seconds"
            previewTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard let self, !Task.isCancelled else { return }
                    let recordingAllowed = await self.recordingAllowsPreview()
                    guard !Task.isCancelled, self.previewRevision == revision else { return }
                    guard self.macOSSpeechIsIdle(), recordingAllowed else {
                        self.stopPreview()
                        self.message = "Preview stopped because speech or recording became active. Audio is saved."
                        return
                    }
                }
            }
        } catch {
            message = "Preview failed: \(error.localizedDescription) The saved version is kept."
        }
    }

    func stopPreview() {
        previewRevision = UUID()
        previewTask?.cancel()
        previewTask = nil
        player?.stop()
        player = nil
        if isPreviewing { message = "Cloned voice preview stopped. Audio is saved." }
        isPreviewing = false
    }

    func revealSelected() {
        if let take = selectedTake { NSWorkspace.shared.activateFileViewerSelecting([audioURL(for: take)]) }
    }

    func audioURL(for take: ClipboardAudioTake) -> URL {
        directory.appendingPathComponent(take.id.uuidString).appendingPathComponent("audio.wav")
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let playerID = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, self.player.map({ ObjectIdentifier($0) }) == playerID else { return }
            self.stopPreview()
            self.message = flag ? "Cloned voice preview finished. Audio is saved." : "Preview did not finish. Audio is saved."
        }
    }
}
