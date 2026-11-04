import Foundation

struct GeneratedClipboardAudio: Sendable {
    let audio: Data
    let voice: UltimateEditorVoice
    let responseJSON: String
}

struct ClonedClipboardAudioClient: Sendable {
    var baseURL = URL(string: "http://localhost:9540")!
    var session = URLSession.shared

    func transcribe(audio: Data, generationResponse: String, takeID: UUID,
                    duration: TimeInterval) async throws -> ClipboardAudioTranscription {
        struct Source: Decodable { let audioUrl: URL }
        let source = try JSONDecoder().decode(Source.self, from: Data(generationResponse.utf8))
        guard ["http", "https"].contains(source.audioUrl.scheme) else {
            throw failure("The saved version has no usable source audio address.")
        }
        // The existing editor endpoint reads a media URL. Verify that its immutable
        // generated WAV still matches our local file before requesting timings.
        var download = URLRequest(url: source.audioUrl)
        download.timeoutInterval = 30
        download.cachePolicy = .reloadIgnoringLocalCacheData
        let (remoteAudio, remoteResponse) = try await session.data(for: download)
        try check(remoteResponse, data: remoteAudio)
        let fingerprint = ClipboardAudioTranscription.fingerprint(audio)
        guard ClipboardAudioTranscription.fingerprint(remoteAudio) == fingerprint else {
            throw failure("The editor’s source audio does not match this local version. Timings were not saved.")
        }
        var transcription = request("api/transcribe-scene", timeout: 900)
        transcription.httpMethod = "POST"
        transcription.setValue("application/json", forHTTPHeaderField: "Content-Type")
        transcription.httpBody = try JSONSerialization.data(withJSONObject: [
            "media_url": source.audioUrl.absoluteString, "model": "tiny", "scene_id": "clipboard-\(takeID.uuidString)",
        ])
        let (data, response) = try await session.data(for: transcription)
        try check(response, data: data)
        struct Segment: Decodable { let words: [ClipboardWordTiming]? }
        struct Payload: Decodable { let text: String; let segments: [Segment] }
        struct Result: Decodable { let response: Payload }
        let result = try JSONDecoder().decode(Result.self, from: data).response
        let saved = ClipboardAudioTranscription(schemaVersion: 1, model: "tiny.en", audioSHA256: fingerprint,
            createdAt: Date(), text: result.text, duration: duration, words: result.segments.flatMap { $0.words ?? [] })
        guard saved.hasValidTimings else {
            throw failure("Tiny.en did not return usable word timings. Your approved audio is unchanged; retry transcription.")
        }
        return saved
    }

    func generate(text: String, voiceID: String, requestID: UUID) async throws -> GeneratedClipboardAudio {
        struct Library: Decodable { let entries: [UltimateEditorVoice] }
        let (presets, presetResponse) = try await session.data(for: request("api/tts-audio-references", timeout: 15))
        try check(presetResponse, data: presets)
        let library = try JSONDecoder().decode(Library.self, from: presets)
        guard let voice = library.entries.first(where: { $0.id == voiceID }),
              voice.enabled, voice.language.lowercased() == "en" || voice.language.lowercased().hasPrefix("en-"),
              ["omnivoice", "omnivoice-lora"].contains(voice.provider) else {
            throw failure("Your saved English voice is unavailable. Refresh the voice list and choose an enabled voice.")
        }

        var generation = request("api/generate-tts-selected", timeout: 900)
        generation.httpMethod = "POST"
        generation.setValue("application/json", forHTTPHeaderField: "Content-Type")
        generation.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": text,
            // This route requires a scene label for filenames; it does not write Baserow rows.
            "sceneId": "clipboard-\(requestID.uuidString)",
            "referenceAudioFilename": voice.id,
            "ttsSettings": ["provider": voice.provider],
        ])
        let (result, response) = try await session.data(for: generation)
        try check(response, data: result)
        struct Result: Decodable { let audioUrl: String }
        let output = try JSONDecoder().decode(Result.self, from: result)
        guard let url = URL(string: output.audioUrl), ["http", "https"].contains(url.scheme) else {
            throw failure("The editor returned an invalid audio address.")
        }
        var download = URLRequest(url: url)
        download.timeoutInterval = 120
        let (audio, audioResponse) = try await session.data(for: download)
        try check(audioResponse, data: audio)
        guard audio.count > 44, audio.starts(with: Data("RIFF".utf8)),
              audio.subdata(in: 8..<12) == Data("WAVE".utf8) else {
            throw failure("The editor did not return a valid WAV recording.")
        }
        return GeneratedClipboardAudio(audio: audio, voice: voice,
                                       responseJSON: String(decoding: result, as: UTF8.self))
    }

    private func request(_ path: String, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    private func check(_ response: URLResponse, data: Data) throws {
        guard let response = response as? HTTPURLResponse else {
            throw failure("The editor returned an invalid response.")
        }
        guard (200..<300).contains(response.statusCode) else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw failure(json?["error"] as? String ?? "Request failed (HTTP \(response.statusCode)).")
        }
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "ClonedClipboardAudio", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
