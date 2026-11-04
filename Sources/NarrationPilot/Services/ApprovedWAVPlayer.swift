import AVFoundation
import Foundation

/// Output-only engine. It is prepared before capture resumes and remains warm
/// between takes; it does not access the microphone or alter macOS speech.
@MainActor
private final class ApprovedAudioOutput {
    static let shared = ApprovedAudioOutput()
    let engine = AVAudioEngine()
    let node = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    private(set) var owner: UUID?
    private var idleTask: Task<Void, Never>?

    private init() { engine.attach(node) }

    func prepare(owner: UUID, format: AVAudioFormat) throws -> Bool {
        guard self.owner == nil else {
            throw NSError(domain: "ApprovedAudioRecording", code: 7,
                userInfo: [NSLocalizedDescriptionKey: "Another approved audio player is active."])
        }
        idleTask?.cancel(); idleTask = nil
        let wasWarm = engine.isRunning && self.format == format
        if self.format != format {
            node.stop(); engine.stop()
            if self.format != nil { engine.disconnectNodeOutput(node) }
            engine.connect(node, to: engine.mainMixerNode, format: format)
            self.format = format
        }
        if !engine.isRunning { engine.prepare(); try engine.start() }
        node.stop()
        self.owner = owner
        return wasWarm
    }

    func release(_ owner: UUID) {
        guard self.owner == owner else { return }
        self.owner = nil
        node.stop()
        idleTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, self.owner == nil else { return }
            self.engine.pause()
        }
    }
}

@MainActor
final class ApprovedWAVPlayer: ApprovedAudioPlaying {
    var completion: ((Bool) -> Void)?
    let duration: TimeInterval
    let clockSource = "AVAudioPlayerNode.playerTime"
    private let output = ApprovedAudioOutput.shared
    private let owner = UUID()
    private let buffer: AVAudioPCMBuffer
    private var generation = UUID()
    private var didStart = false
    private var finished = false
    private var stopped = false
    private var stoppedTime: TimeInterval = 0
    private var configurationObserver: NSObjectProtocol?
    private let preparationMilliseconds: Double
    private let reusedWarmEngine: Bool

    var timingDiagnostics: [String: Double] {
        ["preparationMilliseconds": preparationMilliseconds,
         "reusedWarmEngine": reusedWarmEngine ? 1 : 0,
         "reportedOutputLatencyMilliseconds": output.node.outputPresentationLatency * 1000,
         "reportedDeviceLatencyMilliseconds": output.engine.outputNode.presentationLatency * 1000]
    }

    var currentTime: TimeInterval {
        if finished { return duration }
        if stopped { return stoppedTime }
        guard didStart, let render = output.node.lastRenderTime,
              let time = output.node.playerTime(forNodeTime: render), time.sampleRate > 0 else { return 0 }
        return min(duration, max(0, Double(time.sampleTime) / time.sampleRate))
    }

    init(audio: Data) throws {
        let began = ProcessInfo.processInfo.systemUptime
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try audio.write(to: temporary, options: .atomic)
        let file = try AVAudioFile(forReading: temporary)
        guard file.length > 0, file.length <= Int64(UInt32.max), file.processingFormat.sampleRate > 0,
              let pcm = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw NSError(domain: "ApprovedAudioRecording", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The approved WAV cannot be decoded for playback."])
        }
        try file.read(into: pcm)
        guard pcm.frameLength > 0 else {
            throw NSError(domain: "ApprovedAudioRecording", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The approved WAV has no audio samples."])
        }
        buffer = pcm
        duration = Double(pcm.frameLength) / pcm.format.sampleRate
        reusedWarmEngine = try output.prepare(owner: owner, format: pcm.format)
        preparationMilliseconds = (ProcessInfo.processInfo.systemUptime - began) * 1000
        let expected = generation
        // dataPlayedBack, rather than dataConsumed/dataRendered, prevents the
        // finishing action from cutting off samples still queued for output.
        output.node.scheduleBuffer(pcm, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == expected, self.didStart, !self.stopped else { return }
                self.finished = true
                self.completion?(true)
            }
        }
        configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
            object: output.engine, queue: nil) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.didStart, !self.stopped, !self.finished, !self.output.engine.isRunning else { return }
                    self.completion?(false)
                }
            }
    }

    func play() -> Bool {
        guard !didStart, !stopped, output.owner == owner, output.engine.isRunning else { return false }
        didStart = true
        output.node.play()
        return output.node.isPlaying
    }

    func stop() {
        guard !stopped else { return }
        stoppedTime = currentTime
        stopped = true; generation = UUID()
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        output.release(owner)
    }
}
