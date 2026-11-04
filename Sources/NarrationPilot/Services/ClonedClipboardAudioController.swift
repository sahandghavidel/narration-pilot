import AppKit
import AVFoundation
import Combine
import CryptoKit
import Foundation

enum ClipboardAudioGrouping {
    static func key(text: String, voiceID: String) -> String {
        let normalized = SpokenTextSanitizer.preparingForSpeech(text, includesBracketedDirections: false)
        return SHA256.hash(data: Data("\(voiceID.utf8.count):\(voiceID)\(normalized)".utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    static func folder(text: String, voiceID: String) -> String {
        let normalized = SpokenTextSanitizer.preparingForSpeech(text, includesBracketedDirections: false)
        let words = normalized.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: "-")
        let slug = String(words.prefix(40))
        return "\(slug.isEmpty ? "narration" : slug)--\(key(text: normalized, voiceID: voiceID))"
    }
}

private struct ClipboardAudioGroupState: Codable {
    let narration: String
    let voiceID: String
    var approvedVersionID: UUID?
}

struct ClipboardAudioTake: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let clipboardText: String
    let spokenText: String
    let voice: UltimateEditorVoice
    let duration: TimeInterval
    let generationResponse: String

    var groupID: String { ClipboardAudioGrouping.key(text: spokenText, voiceID: voice.id) }

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
    @Published private(set) var approvedVersions: [String: UUID] = [:]
    @Published private(set) var transcriptions: [UUID: ClipboardAudioTranscription] = [:]
    @Published private(set) var transcribingIDs: Set<UUID> = []
    @Published private(set) var transcriptionErrors: [UUID: String] = [:]
    @Published private(set) var isGenerating = false
    @Published private(set) var isPreviewing = false
    @Published private(set) var message = "Copy one scene’s narration, then generate a cloned voice preview."
    var macOSSpeechIsIdle: () -> Bool = { true }
    var approvedRecordingIsActive: () -> Bool = { false }
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
        var loaded: [ClipboardAudioTake] = []
        for folder in folders {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("group.json")),
                  let group = try? JSONDecoder().decode(ClipboardAudioGroupState.self, from: data),
                  folder.lastPathComponent == ClipboardAudioGrouping.folder(text: group.narration, voiceID: group.voiceID) else { continue }
            let key = ClipboardAudioGrouping.key(text: group.narration, voiceID: group.voiceID)
            approvedVersions[key] = group.approvedVersionID
            let versions = (try? FileManager.default.contentsOfDirectory(at: folder.appendingPathComponent("versions"),
                includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
            for version in versions {
                guard let id = UUID(uuidString: version.lastPathComponent),
                      let data = try? Data(contentsOf: version.appendingPathComponent("metadata.json")),
                      let take = try? JSONDecoder().decode(ClipboardAudioTake.self, from: data),
                      take.id == id, take.groupID == key,
                      FileManager.default.fileExists(atPath: version.appendingPathComponent("audio.wav").path) else { continue }
                loaded.append(take)
            }
        }
        takes = loaded.sorted { $0.createdAt > $1.createdAt }
        let savedID = defaults.string(forKey: Self.selectedKey).flatMap(UUID.init(uuidString:))
        selectedID = takes.first(where: { $0.id == savedID })?.id ?? takes.first?.id
        if let take = selectedTake { loadCachedTranscription(for: take) }
    }

    var selectedTake: ClipboardAudioTake? { takes.first { $0.id == selectedID } }

    func approvedClipboardAudio() throws -> (take: ClipboardAudioTake, audio: Data) {
        guard let voice = UltimateEditorVoiceLibrary(defaults: defaults).selectedVoice else {
            throw recordingError("Choose the English voice used for your approved audio first.")
        }
        return try approvedAudio(narration: NSPasteboard.general.string(forType: .string) ?? "", voiceID: voice.id)
    }

    func approvedAudio(narration: String, voiceID: String) throws -> (take: ClipboardAudioTake, audio: Data) {
        guard !isGenerating else { throw recordingError("Wait for audio preparation to finish first.") }
        let text = SpokenTextSanitizer.preparingForSpeech(narration, includesBracketedDirections: false)
        guard !text.isEmpty else { throw recordingError("Copy the approved narration to the clipboard first.") }
        let key = ClipboardAudioGrouping.key(text: text, voiceID: voiceID)
        guard let id = approvedVersions[key], let take = takes.first(where: { $0.id == id && $0.groupID == key }) else {
            throw recordingError("No approved audio matches this clipboard narration and voice. Prepare and approve it before recording.")
        }
        // Freeze the exact local bytes before sending any recorder shortcut.
        let audio = try Data(contentsOf: audioURL(for: take))
        guard audio.count > 44, audio.starts(with: Data("RIFF".utf8)), audio.subdata(in: 8..<12) == Data("WAVE".utf8) else {
            throw recordingError("The approved WAV is missing or invalid. Recording was not started.")
        }
        return (take, audio)
    }

    private func recordingError(_ message: String) -> NSError {
        NSError(domain: "ClonedClipboardAudio", code: 6, userInfo: [NSLocalizedDescriptionKey: message])
    }
    var selectedIsApproved: Bool {
        guard let take = selectedTake else { return false }
        return approvedVersions[take.groupID] == take.id
    }
    var narrationGroups: [ClipboardAudioTake] {
        var seen = Set<String>()
        return takes.filter { seen.insert($0.groupID).inserted }
    }
    var selectedVersions: [ClipboardAudioTake] {
        guard let take = selectedTake else { return [] }
        return takes.filter { $0.groupID == take.groupID }
    }

    func selectGroup(_ id: String) {
        if let take = takes.first(where: { $0.groupID == id && $0.id == approvedVersions[id] })
            ?? takes.first(where: { $0.groupID == id }) { select(take.id) }
    }

    @discardableResult
    func approveSelected() -> Task<Void, Never>? {
        guard !isGenerating, let take = selectedTake else { return nil }
        do {
            let validation = try AVAudioPlayer(contentsOf: audioURL(for: take))
            guard validation.duration > 0 else { throw missingApprovedFile() }
            let state = ClipboardAudioGroupState(narration: take.spokenText, voiceID: take.voice.id, approvedVersionID: take.id)
            try JSONEncoder().encode(state).write(to: groupURL(for: take).appendingPathComponent("group.json"), options: .atomic)
            approvedVersions[take.groupID] = take.id
            message = "Approved. This narration and voice will reuse this exact audio next time."
            return transcribeApprovedAudio(take.id)
        } catch { message = "Could not approve audio: \(error.localizedDescription)"; return nil }
    }

    func select(_ id: UUID) {
        guard takes.contains(where: { $0.id == id }) else { return }
        stopPreview()
        selectedID = id
        defaults.set(id.uuidString, forKey: Self.selectedKey)
        if let take = selectedTake { loadCachedTranscription(for: take) }
    }

    func generateClipboard(forceNewVersion: Bool = false) {
        guard !isGenerating else { return }
        guard !approvedRecordingIsActive() else { message = "Finish the cloned audio take before preparing another version."; return }
        let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
        guard let voice = UltimateEditorVoiceLibrary(defaults: defaults).selectedVoice else {
            message = "Choose an English voice in Ultimate Video Editor voice first."
            return
        }
        // Set synchronously so repeated shortcut events cannot enqueue another request.
        isGenerating = true
        Task { await performGeneration(clipboard: clipboard, voiceID: voice.id, forceNewVersion: forceNewVersion) }
    }

    func generate(clipboard: String, voiceID: String, forceNewVersion: Bool = false) async {
        guard !isGenerating else { return }
        isGenerating = true
        await performGeneration(clipboard: clipboard, voiceID: voiceID, forceNewVersion: forceNewVersion)
    }

    private func performGeneration(clipboard: String, voiceID: String, forceNewVersion: Bool) async {
        defer { isGenerating = false }
        let text = SpokenTextSanitizer.preparingForSpeech(clipboard, includesBracketedDirections: false)
        guard !text.isEmpty else { message = "Copy some narration text first."; return }
        guard text.count <= 12000 else { message = "Copy one scene at a time (up to 12,000 characters)."; return }
        guard !approvedRecordingIsActive() else { message = "Finish the cloned audio take before preparing another version."; return }
        guard macOSSpeechIsIdle() else { message = "Wait for macOS speech to finish before generating a cloned preview."; return }
        guard await recordingAllowsPreview() else {
            message = "Pause FocuSee before generating a preview. Its recording state must be known."
            return
        }
        stopPreview()
        do {
            let key = ClipboardAudioGrouping.key(text: text, voiceID: voiceID)
            if !forceNewVersion, let approvedID = approvedVersions[key] {
                guard let approved = takes.first(where: { $0.id == approvedID && $0.groupID == key }),
                      FileManager.default.fileExists(atPath: audioURL(for: approved).path) else { throw missingApprovedFile() }
                // Audio reuse is local; missing timings can fill in the background.
                select(approved.id)
                message = "Reusing approved audio. No generation requested."
                transcribeApprovedAudio(approved.id)
                await previewSelected()
                return
            }
            message = "Generating cloned clipboard audio…"
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
        let group = groupURL(for: take)
        let versions = group.appendingPathComponent("versions", isDirectory: true)
        try FileManager.default.createDirectory(at: versions, withIntermediateDirectories: true)
        let groupFile = group.appendingPathComponent("group.json")
        if !FileManager.default.fileExists(atPath: groupFile.path) {
            let state = ClipboardAudioGroupState(narration: text, voiceID: generated.voice.id)
            try JSONEncoder().encode(state).write(to: groupFile, options: .atomic)
        }
        let staging = versions.appendingPathComponent(".\(id.uuidString).pending", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: staging) }
        try generated.audio.write(to: staging.appendingPathComponent("audio.wav"), options: .atomic)
        try JSONEncoder().encode(take).write(to: staging.appendingPathComponent("metadata.json"), options: .atomic)
        try FileManager.default.moveItem(at: staging, to: versions.appendingPathComponent(id.uuidString, isDirectory: true))
        return take
    }

    func previewSelected() async {
        guard let take = selectedTake else { return }
        guard !approvedRecordingIsActive() else { message = "Finish the cloned audio take before previewing another version."; return }
        stopPreview()
        let revision = previewRevision
        let recordingAllowed = await recordingAllowsPreview()
        guard revision == previewRevision, selectedID == take.id else { return }
        guard macOSSpeechIsIdle(), recordingAllowed, !approvedRecordingIsActive() else {
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
            message = "Previewing \(selectedIsApproved ? "approved audio" : "cloned voice") · \(take.duration.formatted(.number.precision(.fractionLength(1)))) seconds"
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
        groupURL(for: take).appendingPathComponent("versions").appendingPathComponent(take.id.uuidString).appendingPathComponent("audio.wav")
    }

    var selectedTranscriptionStatus: String {
        guard let take = selectedTake else { return "" }
        if transcribingIDs.contains(take.id) { return "Transcribing with Tiny.en…" }
        if let error = transcriptionErrors[take.id] { return "Transcription failed: \(error)" }
        if let saved = transcriptions[take.id] { return "Timings ready · Tiny.en · \(saved.words.count) words" }
        return selectedIsApproved ? "Word timings have not been saved yet." : "Approve this version to create word timings."
    }

    func transcriptionURL(for take: ClipboardAudioTake) -> URL {
        audioURL(for: take).deletingLastPathComponent().appendingPathComponent("transcription.json")
    }

    private func loadCachedTranscription(for take: ClipboardAudioTake) {
        guard let audio = try? Data(contentsOf: audioURL(for: take)),
              let data = try? Data(contentsOf: transcriptionURL(for: take)),
              let saved = try? JSONDecoder().decode(ClipboardAudioTranscription.self, from: data),
              saved.hasValidTimings, saved.audioSHA256 == ClipboardAudioTranscription.fingerprint(audio) else {
            transcriptions[take.id] = nil
            return
        }
        transcriptions[take.id] = saved
        transcriptionErrors[take.id] = nil
    }

    @discardableResult
    func transcribeApprovedAudio(_ id: UUID) -> Task<Void, Never>? {
        guard let take = takes.first(where: { $0.id == id }), approvedVersions[take.groupID] == id,
              !transcribingIDs.contains(id) else { return nil }
        loadCachedTranscription(for: take)
        if transcriptions[id] != nil { return nil }
        transcribingIDs.insert(id)
        transcriptionErrors[id] = nil
        return Task { [weak self] in
            guard let self else { return }
            defer { self.transcribingIDs.remove(id) }
            do {
                let audio = try Data(contentsOf: self.audioURL(for: take))
                let validation = try AVAudioPlayer(data: audio)
                let saved = try await self.client.transcribe(audio: audio, generationResponse: take.generationResponse,
                    takeID: id, duration: validation.duration)
                let currentAudio = try Data(contentsOf: self.audioURL(for: take))
                guard saved.audioSHA256 == ClipboardAudioTranscription.fingerprint(currentAudio) else {
                    throw NSError(domain: "ClonedClipboardAudio", code: 5, userInfo: [NSLocalizedDescriptionKey:
                        "The local audio changed during transcription. Retry with the correct saved version."])
                }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(saved).write(to: self.transcriptionURL(for: take), options: .atomic)
                self.transcriptions[id] = saved
            } catch {
                self.transcriptionErrors[id] = error.localizedDescription
            }
        }
    }

    private func groupURL(for take: ClipboardAudioTake) -> URL {
        directory.appendingPathComponent(ClipboardAudioGrouping.folder(text: take.spokenText, voiceID: take.voice.id), isDirectory: true)
    }

    private func missingApprovedFile() -> NSError {
        NSError(domain: "ClonedClipboardAudio", code: 4, userInfo: [NSLocalizedDescriptionKey:
            "The approved file is missing or unreadable. Use Generate New Version explicitly to replace it."])
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
