import Foundation

@main
struct AgentFeedbackCheck {
    @MainActor static func main() throws {
        let suite = "NarrationPilot.AgentFeedbackCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let feedback = AgentFeedbackPublisher(defaults: defaults, directory: directory)
        func publish(_ scene: String = "B") {
            feedback.publish(scene: ["sceneID": scene, "narration": "Scene \(scene)"], speech: "idle",
                             passage: "Test passage", word: "Test", estimatedDuration: 10, message: "Ready")
        }
        func snapshot() throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: feedback.lastData!) as! [String: Any]
        }
        publish()
        assert(!FileManager.default.fileExists(atPath: feedback.statusURL.path))
        feedback.enabled = true
        let id = UUID()
        feedback.begin(id: id, scene: ["sceneID": "A"], recordingExpected: true)
        feedback.transition("recordingRequested")
        feedback.observe(.recording)
        feedback.transition("recordingConfirmed")
        publish()
        var data = try snapshot()
        let active = data["activeTake"] as! [String: Any]
        assert(active["id"] as? String == id.uuidString)
        assert((active["scene"] as! [String: Any])["sceneID"] as? String == "A")
        assert((data["currentScene"] as! [String: Any])["sceneID"] as? String == "B")
        assert((data["focuSee"] as! [String: Any])["observedState"] as? String == "recording")
        assert((data["focuSee"] as! [String: Any])["requestedState"] as? String == "recording")
        feedback.transition("narrationFinished")
        feedback.observe(.paused)
        feedback.finish("pauseConfirmed")
        publish()
        data = try snapshot()
        assert(data["activeTake"] is NSNull)
        assert((data["recentTakes"] as! [[String: Any]]).last?["result"] as? String == "pauseConfirmed")
        for _ in 0..<25 {
            feedback.begin(id: UUID(), scene: ["sceneID": "A"], recordingExpected: true)
            feedback.finish("failed", error: "Recording was not confirmed")
        }
        publish()
        data = try snapshot()
        assert((data["recentTakes"] as! [[String: Any]]).count == 20)
        assert((data["events"] as! [[String: String]]).count <= 100)
        let attrs = try FileManager.default.attributesOfItem(atPath: feedback.statusURL.path)
        assert((attrs[.posixPermissions] as! NSNumber).intValue == 0o600)
        feedback.stop()
        let stopped = try JSONSerialization.jsonObject(with: Data(contentsOf: feedback.statusURL)) as! [String: Any]
        assert(stopped["appRunning"] as? Bool == false)
        feedback.enabled = false
        assert(!FileManager.default.fileExists(atPath: feedback.statusURL.path))
        print("PASS: scene/take identity, observed state, completion, failure history bounds, private atomic file, termination, disable cleanup")
    }
}
