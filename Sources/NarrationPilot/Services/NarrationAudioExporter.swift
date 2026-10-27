import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// Exports with the system engine used by default narration playback.
@MainActor
final class NarrationAudioExporter: NSObject, ObservableObject, NSSpeechSynthesizerDelegate {
    @Published private(set) var isExporting = false
    @Published private(set) var message = ""
    private var synthesizer: NSSpeechSynthesizer?
    private var temporaryURL: URL?
    private var destinationURL: URL?

    nonisolated static func spokenSegments(_ texts: [String]) -> [String] {
        texts.map { SpokenTextSanitizer.preparingForSpeech($0, includesBracketedDirections: false) }
            .filter { !$0.isEmpty }
    }

    nonisolated static func estimatedDuration(texts: [String], speed: Double) -> TimeInterval {
        let words = spokenSegments(texts).reduce(0) {
            $0 + $1.split(whereSeparator: { $0.isWhitespace }).count
        }
        return Double(words) / (175 * SpeechRateMapper.clampMultiplier(speed)) * 60
    }

    nonisolated static func durationLabel(_ seconds: TimeInterval) -> String {
        let rounded = max(0, Int(seconds.rounded()))
        return "\(rounded / 60)m \(rounded % 60)s"
    }

    func save(texts: [String], speed: Double, voiceIdentifier: String?, filename: String) {
        guard !isExporting else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.aiff]
        panel.nameFieldStringValue = filename.replacingOccurrences(of: "/", with: "-") + ".aiff"
        guard let window = NSApp.keyWindow else {
            message = "Open the scene manager before saving audio."
            return
        }
        panel.beginSheetModal(for: window) { [self] response in
            guard response == .OK, let destination = panel.url else { return }
            export(texts: texts, speed: speed, voiceIdentifier: voiceIdentifier, to: destination)
        }
    }

    /// Also used by the standalone export verification, without presenting a save dialog.
    func export(texts: [String], speed: Double, voiceIdentifier: String?, to destination: URL) {
        guard !isExporting else { return }
        let text = Self.spokenSegments(texts).joined(separator: "\n\n")
        guard !text.isEmpty else { return }
        let voice = voiceIdentifier.flatMap { $0.isEmpty ? nil : NSSpeechSynthesizer.VoiceName(rawValue: $0) }
        if let voice, !NSSpeechSynthesizer.availableVoices.contains(voice) {
            message = "This playback voice does not support file export. Choose System Default or another installed system voice."
            return
        }
        guard let engine = NSSpeechSynthesizer(voice: voice) else {
            message = "The selected voice could not be opened for export."
            return
        }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".aiff")
        temporaryURL = temporary
        destinationURL = destination
        synthesizer = engine
        engine.delegate = self
        engine.rate = Float(175 * SpeechRateMapper.clampMultiplier(speed))
        isExporting = true
        message = "Generating audio…"
        if !engine.startSpeaking(text, to: temporary) {
            finish(error: "This voice could not generate an audio file. Try another system voice.")
        }
    }

    func cancel() {
        synthesizer?.delegate = nil
        synthesizer?.stopSpeaking(at: .immediateBoundary)
        finish(error: "Audio export cancelled.")
    }

    func speechSynthesizer(_ sender: NSSpeechSynthesizer, didFinishSpeaking finishedSpeaking: Bool) {
        guard isExporting, sender === synthesizer else { return }
        guard finishedSpeaking, let temporaryURL, let destinationURL else {
            finish(error: "Audio generation failed. Try another system voice.")
            return
        }
        do {
            let file = try AVAudioFile(forReading: temporaryURL)
            guard file.length > 0 else {
                finish(error: "The voice generated no audio. Try another system voice.")
                return
            }
            let duration = Double(file.length) / file.processingFormat.sampleRate
            // Atomic write keeps an existing destination intact if generation or saving fails.
            try Data(contentsOf: temporaryURL).write(to: destinationURL, options: .atomic)
            finish(error: "Saved \(destinationURL.lastPathComponent) · Audio: \(Self.durationLabel(duration))")
        } catch {
            finish(error: "Could not save audio: \(error.localizedDescription)")
        }
    }

    private func finish(error message: String) {
        synthesizer?.delegate = nil
        synthesizer = nil
        if let temporaryURL { try? FileManager.default.removeItem(at: temporaryURL) }
        temporaryURL = nil
        destinationURL = nil
        isExporting = false
        self.message = message
    }
}
