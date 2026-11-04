import Combine
import Foundation

struct GuidedNarrationDraft: Codable, Equatable, Sendable {
    var sessionID: UUID
    var sceneID: String
    var revision: Int
    var narration: String
}

struct GuidedNarrationDecision: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var id: UUID
    var kind: String
    var draft: GuidedNarrationDraft
    var createdAt: Date
}

struct GuidedNarrationCommand: Codable, Sendable {
    var schemaVersion = 1
    var createdAt = Date()
    var id: UUID
    var sessionID: UUID
    var kind: String
    var draft: GuidedNarrationDraft?
    var eventID: UUID?
}

struct GuidedNarrationSnapshot: Codable {
    var schemaVersion = 1
    var appRunning: Bool
    var pid: Int32
    var updatedAt: Date
    var active: Bool
    var phase: String
    var message: String
    var draft: GuidedNarrationDraft?
    var decision: GuidedNarrationDecision?
    var acknowledged: Bool
    var speechActive: Bool
}

/// Local narration-only handshake. It never touches the clipboard, cloned TTS,
/// recordings, or the existing speech controller. An active agent reads events
/// and submits revisions through the inbox; a file does not launch an agent.
@MainActor
final class GuidedNarrationReview: ObservableObject {
    nonisolated static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/local.clipboardreadermac/GuidedNarrationReview")
    @Published private(set) var active = false
    @Published private(set) var phase = "inactive"
    @Published private(set) var message = "No guided narration review is active."
    @Published private(set) var draft: GuidedNarrationDraft?
    @Published private(set) var decision: GuidedNarrationDecision?
    @Published private(set) var acknowledged = false
    var canSpeak: () async -> String? = { "Guided speech is not connected." }
    var speak: (String, UUID) -> Void = { _, _ in }
    var stopSpeech: () -> Void = {}

    let directory: URL
    private var timer: Timer?
    private var processing = false
    private var checkingSpeech = false
    private var speechToken: UUID?
    private var running = false
    private var generation = UUID()
    private var lastHeartbeat = Date.distantPast

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder
    }
    static func decoder() -> JSONDecoder { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder }

    init(directory: URL = GuidedNarrationReview.directory) {
        self.directory = directory
        do {
            try prepareDirectories()
            if let data = try? Data(contentsOf: directory.appendingPathComponent("status.json")),
               let saved = try? Self.decoder().decode(GuidedNarrationSnapshot.self, from: data), saved.schemaVersion == 1 {
                draft = saved.draft; active = saved.active
                if let draft, active {
                    decision = try? Self.decoder().decode(GuidedNarrationDecision.self, from: Data(contentsOf: eventURL(draft)))
                    acknowledged = decision.map { FileManager.default.fileExists(atPath: acknowledgmentURL($0.id).path) } ?? false
                    phase = decision.map { $0.kind == "approveNarration" ? "approved" : "improving" } ?? "suspended"
                    message = decision == nil ? "Review restored. Replay the narration to resume; no speech starts automatically." : "Saved decision restored. Waiting for the agent."
                }
            }
        } catch { message = "Cannot prepare narration review: \(error.localizedDescription)" }
    }

    func start() {
        guard timer == nil else { return }
        running = true
        publish()
        timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.processInbox() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func stop() {
        running = false; timer?.invalidate(); timer = nil
        interruptSpeech()
        publish()
    }

    func speechFinished(_ token: UUID) {
        guard token == speechToken else { return }
        speechToken = nil
        if active, phase == "reading" {
            phase = "awaitingDecision"
            message = "Review narration: use the approval shortcut for wording, or regeneration shortcut to request improvement."
        }
        publish()
    }

    func speechFailed(_ token: UUID) {
        guard token == speechToken else { return }
        speechToken = nil
        if active, decision == nil { phase = "blocked" }
        message = "Spoken prompt failed. The draft and any saved decision are retained; use Replay Narration when ready."
        publish()
    }

    func interruptSpeech() {
        speechToken = nil; generation = UUID(); checkingSpeech = false
        stopSpeech()
        if active, decision == nil, phase == "reading" || phase == "checking" {
            phase = "suspended"; message = "Narration preview interrupted. Replay it when speech and recording are idle."
        }
        publish()
    }

    /// Returns true whenever guided review owns A/G, including locked stages.
    @discardableResult func approve() -> Bool { choose("approveNarration"); return active }
    @discardableResult func improve() -> Bool { choose("improveNarration"); return active }

    private func choose(_ kind: String) {
        guard active, let draft, decision == nil,
              phase == "reading" || phase == "awaitingDecision" else { return }
        let event = GuidedNarrationDecision(id: UUID(), kind: kind, draft: draft, createdAt: Date())
        do {
            // One immutable event file per revision is authoritative across crashes.
            let url = eventURL(draft)
            guard !FileManager.default.fileExists(atPath: url.path) else { return }
            try write(event, to: url)
            decision = event; acknowledged = false
            phase = kind == "approveNarration" ? "approved" : "improving"
            message = kind == "approveNarration" ? "Narration approved. Waiting for the agent to receive it." : "Improvement requested. Waiting for the agent."
            speechToken = nil; generation = UUID(); stopSpeech()
            publish()
            let prompt = kind == "approveNarration" ? "Narration approved." : "Improvement requested. Waiting for the agent."
            Task { [weak self] in
                guard let self, self.decision?.id == event.id else { return }
                await self.announce(prompt)
            }
        } catch { message = "Decision was not saved: \(error.localizedDescription). Please retry."; publish() }
    }

    func replay() async {
        guard active, draft != nil, decision == nil, !checkingSpeech else { return }
        checkingSpeech = true
        let expected = generation
        phase = "checking"; publish()
        let issue = await canSpeak()
        guard expected == generation, active, decision == nil else { return }
        checkingSpeech = false
        if let issue { phase = "blocked"; message = issue; publish(); return }
        let token = UUID(); speechToken = token
        phase = "reading"; message = "Reading narration. Approval accepts these exact words; redo requests an improved draft."
        publish()
        speak("Review narration. \(draft!.narration) End of narration. Use your approval shortcut to approve the wording, or your redo shortcut to request improvement.", token)
    }

    private func announce(_ text: String) async {
        let expected = generation
        guard await canSpeak() == nil, expected == generation, active else { return }
        let token = UUID(); speechToken = token; publish(); speak(text, token)
    }

    func end() {
        generation = UUID(); speechToken = nil; checkingSpeech = false; stopSpeech()
        active = false; phase = "inactive"; message = "Guided narration review ended. Audio approval and regeneration shortcuts are available."
        publish()
    }

    func processInbox() async {
        guard !processing else { return }
        processing = true
        defer { processing = false }
        if Date().timeIntervalSince(lastHeartbeat) >= 1 { publish(); lastHeartbeat = Date() }
        let files = ((try? FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("commands"), includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) < ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        for file in files {
            guard UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil else { continue }
            let receipt = directory.appendingPathComponent("receipts/\(file.lastPathComponent)")
            guard !FileManager.default.fileExists(atPath: receipt.path) else { continue }
            do {
                let command = try Self.decoder().decode(GuidedNarrationCommand.self, from: Data(contentsOf: file))
                guard command.schemaVersion == 1, file.deletingPathExtension().lastPathComponent.lowercased() == command.id.uuidString.lowercased() else { throw error("Invalid command identity or schema.") }
                guard Date().timeIntervalSince(command.createdAt) <= 120,
                      Date().timeIntervalSince(command.createdAt) >= -5 else { throw error("Command expired. Submit a fresh command after checking the current review.") }
                try await handle(command)
                try writeReceipt(commandID: command.id.uuidString, accepted: true, message: message, to: receipt)
            } catch {
                try? writeReceipt(commandID: file.deletingPathExtension().lastPathComponent, accepted: false, message: error.localizedDescription, to: receipt)
            }
        }
    }

    private func handle(_ command: GuidedNarrationCommand) async throws {
        switch command.kind {
        case "submit":
            guard let next = command.draft, next.sessionID == command.sessionID,
                  !next.sceneID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, next.sceneID.count <= 200,
                  next.revision > 0, next.revision <= 100000,
                  !next.narration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, next.narration.count <= 12000 else { throw error("Invalid narration draft.") }
            if active {
                guard let previous = draft, previous.sessionID == next.sessionID, previous.sceneID == next.sceneID else { throw error("Another narration review is active. End it before starting a new session.") }
                if previous == next { return } // Retry never repeats speech or changes a decision.
                guard let decision, decision.kind == "improveNarration", command.eventID == decision.id,
                      next.revision == previous.revision + 1 else { throw error("A revision must answer the current improvement event and increment the revision once.") }
            } else {
                guard next.revision == 1, !FileManager.default.fileExists(atPath: eventURL(next).path) else { throw error("Start a new review with a fresh session ID and revision 1.") }
            }
            generation = UUID(); speechToken = nil; stopSpeech()
            draft = next; active = true; decision = nil; acknowledged = false; checkingSpeech = false
            phase = "ready"; message = "Narration received. Preparing the spoken review."; publish()
            await replay()
        case "acknowledge":
            guard active, let decision, decision.draft.sessionID == command.sessionID, decision.id == command.eventID else { throw error("Acknowledgment does not match the current decision.") }
            if acknowledged { return }
            try writeReceipt(commandID: command.id.uuidString, accepted: true, message: "Decision received by the agent.", to: acknowledgmentURL(decision.id))
            acknowledged = true
            message = decision.kind == "approveNarration" ? "Narration approved and received by the agent. Cloned TTS is not started in this first step." : "Agent received the improvement request. Waiting for revised narration."
            publish()
            // Do not interrupt the decision confirmation with another spoken prompt.
        case "replay":
            guard active, draft?.sessionID == command.sessionID, decision == nil else { throw error("This review has no draft waiting for a decision.") }
            await replay()
        case "end":
            guard draft?.sessionID == command.sessionID else { throw error("Session does not match the current review.") }
            end()
        default: throw error("Unknown narration review command.")
        }
    }

    private func eventURL(_ draft: GuidedNarrationDraft) -> URL {
        directory.appendingPathComponent("events/\(draft.sessionID.uuidString.lowercased())-r\(draft.revision).json")
    }
    private func acknowledgmentURL(_ id: UUID) -> URL { directory.appendingPathComponent("acknowledgments/\(id.uuidString.lowercased()).json") }
    private func prepareDirectories() throws {
        for name in ["", "commands", "receipts", "events", "acknowledgments"] {
            let url = directory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }
    }
    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try Self.encoder().encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func writeReceipt(commandID: String, accepted: Bool, message: String, to url: URL) throws {
        struct Receipt: Encodable { var schemaVersion = 1; var commandID: String; var accepted: Bool; var message: String; var updatedAt: Date }
        try write(Receipt(commandID: commandID, accepted: accepted, message: message, updatedAt: Date()), to: url)
    }
    private func publish() {
        do {
            try write(GuidedNarrationSnapshot(appRunning: running, pid: ProcessInfo.processInfo.processIdentifier, updatedAt: Date(), active: active, phase: phase, message: message, draft: draft, decision: decision, acknowledged: acknowledged, speechActive: speechToken != nil), to: directory.appendingPathComponent("status.json"))
        } catch { message = "Could not save narration review status: \(error.localizedDescription)" }
    }
    private func error(_ text: String) -> NSError { NSError(domain: "GuidedNarrationReview", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}
