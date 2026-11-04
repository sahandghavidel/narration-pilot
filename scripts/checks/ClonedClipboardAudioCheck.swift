import Foundation

// Compile with the production client/controller and dependencies; uses no real service or playback.
private final class FixtureState: @unchecked Sendable {
    let lock = NSLock()
    var brokenAudio = false
    var postCount = 0
    var requestCount = 0
    var transcriptionCount = 0
    var transcriptionFails = false
    var emptyTimings = false
    let voice = UltimateEditorVoice(id: "test-voice", name: "Test Voice", provider: "omnivoice-lora", language: "en", enabled: true)

    func response(_ request: URLRequest) throws -> (Int, Data) {
        lock.lock(); defer { lock.unlock() }
        requestCount += 1
        switch request.url!.path {
        case "/api/tts-audio-references":
            return (200, try JSONEncoder().encode(["entries": [voice]]))
        case "/api/generate-tts-selected":
            let bytes: Data
            if let body = request.httpBody { bytes = body }
            else {
                let stream = request.httpBodyStream!
                stream.open(); defer { stream.close() }
                var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    data.append(contentsOf: buffer.prefix(count))
                }
                bytes = data
            }
            let body = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
            precondition(body["referenceAudioFilename"] as? String == voice.id)
            precondition((body["sceneId"] as? String)?.hasPrefix("clipboard-") == true)
            precondition((body["ttsSettings"] as? [String: String])?["provider"] == voice.provider)
            precondition(body["videoId"] == nil)
            postCount += 1
            return (200, Data(#"{"audioUrl":"https://fixture.invalid/audio.wav","generationParams":{"seed":123,"referencePresetId":"test-voice"}}"#.utf8))
        case "/audio.wav":
            return (200, brokenAudio ? Data("not audio".utf8) : Self.wav())
        case "/api/transcribe-scene":
            let body = try JSONSerialization.jsonObject(with: Self.bodyData(request)) as! [String: Any]
            precondition(body["model"] as? String == "tiny")
            precondition((body["scene_id"] as? String)?.hasPrefix("clipboard-") == true)
            transcriptionCount += 1
            if transcriptionFails { return (503, Data(#"{"error":"Fixture transcription failure"}"#.utf8)) }
            if emptyTimings { return (200, Data(#"{"response":{"text":"Hello world.","segments":[]}}"#.utf8)) }
            return (200, Data(#"{"response":{"text":"Hello world.","segments":[{"words":[{"word":"Hello","start":0,"end":0.04},{"word":"world.","start":0.04,"end":0.09}]}],"duration":0.1}}"#.utf8))
        default:
            return (404, Data())
        }
    }

    static func bodyData(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }

    static func wav() -> Data {
        var data = Data("RIFF".utf8)
        func word<T: FixedWidthInteger>(_ value: T) {
            var value = value.littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        let samples = 2400
        word(UInt32(36 + samples * 2)); data.append(Data("WAVEfmt ".utf8))
        word(UInt32(16)); word(UInt16(1)); word(UInt16(1)); word(UInt32(24000))
        word(UInt32(48000)); word(UInt16(2)); word(UInt16(16)); data.append(Data("data".utf8))
        word(UInt32(samples * 2)); data.append(Data(repeating: 0, count: samples * 2))
        return data
    }
}

private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    static let fixture = FixtureState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (code, data) = try Self.fixture.response(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@main
struct ClonedClipboardAudioCheck {
    @MainActor static func main() async throws {
        let suite = "NarrationPilot.ClonedClipboardCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let api = ClonedClipboardAudioClient(baseURL: URL(string: "https://fixture.invalid")!, session: session)
        let audio = ClonedClipboardAudioController(directory: folder, defaults: defaults, client: api)
        audio.recordingAllowsPreview = { true }
        var idleChecks = 0
        // Allow generation but prevent audible preview in this check.
        audio.macOSSpeechIsIdle = { idleChecks += 1; return idleChecks == 1 }
        await audio.generate(clipboard: "[Click] Hello world.", voiceID: "test-voice")
        precondition(audio.takes.count == 1, audio.message)
        let first = audio.selectedTake!
        precondition(first.clipboardText == "[Click] Hello world.")
        precondition(first.spokenText == "Hello world.")
        precondition(first.duration > 0)
        precondition(!audio.isPreviewing && !audio.isGenerating)
        let original = try Data(contentsOf: audio.audioURL(for: first))
        idleChecks = 0
        await audio.generate(clipboard: "[New direction] Hello   world.", voiceID: "test-voice")
        precondition(audio.takes.count == 2)
        precondition(first.id != audio.selectedID)
        precondition(audio.selectedTake!.groupID == first.groupID)
        precondition(audio.audioURL(for: first).deletingLastPathComponent().deletingLastPathComponent()
                     == audio.audioURL(for: audio.selectedTake!).deletingLastPathComponent().deletingLastPathComponent())
        let retained = try Data(contentsOf: audio.audioURL(for: first))
        precondition(retained == original)
        let selected = audio.selectedID
        FixtureProtocol.fixture.lock.withLock { FixtureProtocol.fixture.brokenAudio = true }
        idleChecks = 0
        await audio.generate(clipboard: "Broken output.", voiceID: "test-voice")
        precondition(audio.takes.count == 2 && audio.selectedID == selected)
        precondition(audio.message.contains("Previous versions are kept"))
        idleChecks = 0
        await audio.generate(clipboard: "Voice missing.", voiceID: "missing")
        precondition(audio.takes.count == 2 && audio.selectedID == selected)
        let restored = ClonedClipboardAudioController(directory: folder, defaults: defaults, client: api)
        precondition(restored.takes.count == 2 && restored.selectedID == selected)
        restored.select(first.id)
        precondition(ClonedClipboardAudioController(directory: folder, defaults: defaults, client: api).selectedID == first.id)
        let posts = FixtureProtocol.fixture.lock.withLock { FixtureProtocol.fixture.postCount }
        restored.recordingAllowsPreview = { false }
        await restored.generate(clipboard: "Blocked recording.", voiceID: "test-voice")
        precondition(FixtureProtocol.fixture.lock.withLock { FixtureProtocol.fixture.postCount } == posts)
        restored.recordingAllowsPreview = { true }
        await restored.generate(clipboard: "  [Direction only] ", voiceID: "test-voice")
        precondition(FixtureProtocol.fixture.lock.withLock { FixtureProtocol.fixture.postCount } == posts)
        // An in-flight request must suppress a second generate action.
        restored.recordingAllowsPreview = { try? await Task.sleep(for: .milliseconds(100)); return false }
        let pending = Task { await restored.generate(clipboard: "First", voiceID: "test-voice") }
        await Task.yield()
        precondition(restored.isGenerating)
        await restored.generate(clipboard: "Duplicate", voiceID: "test-voice")
        await pending.value
        precondition(FixtureProtocol.fixture.lock.withLock { FixtureProtocol.fixture.postCount } == posts)
        // Approval, local reuse without any HTTP, and deliberate regeneration.
        restored.recordingAllowsPreview = { true }
        var previewChecks = 0
        restored.macOSSpeechIsIdle = { previewChecks += 1; return previewChecks == 1 }
        restored.select(first.id)
        FixtureProtocol.fixture.lock.withLock { FixtureProtocol.fixture.brokenAudio = false }
        await restored.approveSelected()?.value
        precondition(restored.selectedIsApproved)
        precondition(restored.transcriptions[first.id]?.words.count == 2)
        precondition(restored.transcriptions[first.id]?.model == "tiny.en")
        let requests = FixtureProtocol.fixture.lock.withLock { FixtureProtocol.fixture.requestCount }
        await restored.generate(clipboard: "[Different direction] Hello\n world.  ", voiceID: "test-voice")
        precondition(restored.selectedID == first.id && restored.takes.count == 2)
        precondition(FixtureProtocol.fixture.lock.withLock { FixtureProtocol.fixture.requestCount } == requests)
        FixtureProtocol.fixture.lock.withLock { FixtureProtocol.fixture.brokenAudio = false }
        previewChecks = 0
        await restored.generate(clipboard: "Hello world.", voiceID: "test-voice", forceNewVersion: true)
        precondition(restored.takes.count == 3 && !restored.selectedIsApproved)
        precondition(restored.approvedVersions[first.groupID] == first.id)
        await restored.approveSelected()?.value
        let approved = restored.selectedTake!
        let reopened = ClonedClipboardAudioController(directory: folder, defaults: defaults, client: api)
        precondition(reopened.selectedIsApproved && reopened.selectedID == approved.id)
        precondition(reopened.transcriptions[approved.id]?.words.count == 2)
        precondition(reopened.narrationGroups.count == 1 && reopened.selectedVersions.count == 3)
        precondition(ClipboardAudioGrouping.key(text: "Hello world!", voiceID: "test-voice") != first.groupID)
        precondition(ClipboardAudioGrouping.key(text: "hello world.", voiceID: "test-voice") != first.groupID)
        precondition(ClipboardAudioGrouping.key(text: "Hello world.", voiceID: "other-voice") != first.groupID)
        // Matching bytes reuse saved timings without any network, even after restart.
        let beforeCached = FixtureProtocol.fixture.lock.withLock { FixtureProtocol.fixture.requestCount }
        precondition(reopened.transcribeApprovedAudio(approved.id) == nil)
        precondition(FixtureProtocol.fixture.lock.withLock { FixtureProtocol.fixture.requestCount } == beforeCached)
        let originalApproved = try Data(contentsOf: reopened.audioURL(for: approved))
        reopened.select(first.id)
        let frozen = try reopened.approvedAudio(narration: "[Record] Hello\n world.", voiceID: "test-voice")
        precondition(frozen.take.id == approved.id && frozen.audio == originalApproved)
        do {
            _ = try reopened.approvedAudio(narration: "Hello world.", voiceID: "unapproved-voice")
            preconditionFailure("Recording must not fall back to another voice")
        } catch { }
        do {
            _ = try reopened.approvedAudio(narration: "Unapproved narration.", voiceID: "test-voice")
            preconditionFailure("Recording must require matching approved audio")
        } catch { }
        reopened.select(approved.id)
        var changed = originalApproved
        changed[changed.count - 1] = 1
        try changed.write(to: reopened.audioURL(for: approved), options: .atomic)
        let transcribeCount = FixtureProtocol.fixture.lock.withLock { FixtureProtocol.fixture.transcriptionCount }
        await reopened.transcribeApprovedAudio(approved.id)?.value
        precondition(reopened.transcriptions[approved.id] == nil)
        precondition(reopened.transcriptionErrors[approved.id]?.contains("does not match") == true)
        precondition(FixtureProtocol.fixture.lock.withLock { FixtureProtocol.fixture.transcriptionCount } == transcribeCount)
        precondition(reopened.selectedIsApproved)
        try originalApproved.write(to: reopened.audioURL(for: approved), options: .atomic)
        try FileManager.default.removeItem(at: reopened.transcriptionURL(for: approved))
        FixtureProtocol.fixture.lock.withLock { FixtureProtocol.fixture.transcriptionFails = true }
        let retry = reopened.transcribeApprovedAudio(approved.id)
        precondition(reopened.transcribeApprovedAudio(approved.id) == nil, "Duplicate transcription must be suppressed")
        await retry?.value
        precondition(reopened.transcriptionErrors[approved.id] != nil && reopened.selectedIsApproved)
        precondition(!FileManager.default.fileExists(atPath: reopened.transcriptionURL(for: approved).path))
        FixtureProtocol.fixture.lock.withLock { FixtureProtocol.fixture.transcriptionFails = false; FixtureProtocol.fixture.emptyTimings = true }
        await reopened.transcribeApprovedAudio(approved.id)?.value
        precondition(reopened.transcriptions[approved.id] == nil && reopened.selectedIsApproved)
        FixtureProtocol.fixture.lock.withLock { FixtureProtocol.fixture.emptyTimings = false }
        await reopened.transcribeApprovedAudio(approved.id)?.value
        precondition(reopened.transcriptions[approved.id]?.words.count == 2 && reopened.transcriptionErrors[approved.id] == nil)
        precondition(FileManager.default.fileExists(atPath: reopened.transcriptionURL(for: first).path))
        try FileManager.default.removeItem(at: reopened.audioURL(for: approved))
        reopened.recordingAllowsPreview = { true }
        let beforeMissing = FixtureProtocol.fixture.lock.withLock { FixtureProtocol.fixture.requestCount }
        await reopened.generate(clipboard: "Hello world.", voiceID: "test-voice")
        precondition(reopened.message.contains("approved file is missing"))
        precondition(FixtureProtocol.fixture.lock.withLock { FixtureProtocol.fixture.requestCount } == beforeMissing)
        reopened.approvedRecordingIsActive = { true }
        await reopened.generate(clipboard: "Hello world.", voiceID: "test-voice")
        precondition(reopened.message.contains("Finish the cloned audio take"))
        await reopened.previewSelected()
        precondition(reopened.message.contains("before previewing"))
        precondition(FixtureProtocol.fixture.lock.withLock { FixtureProtocol.fixture.requestCount } == beforeMissing)
        print("PASS: grouped approval/reuse plus Tiny.en timings, fingerprint invalidation, restart cache, failure/retry, empty timestamps, duplicate suppression and independent version caches; no real playback")
    }
}
