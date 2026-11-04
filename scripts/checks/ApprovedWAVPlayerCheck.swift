import Foundation

// Plays only generated silence. Never opens or controls FocuSee, TTS, or macOS speech.
@main
struct ApprovedWAVPlayerCheck {
    @MainActor static func main() async throws {
        var wav = Data("RIFF".utf8)
        func word<T: FixedWidthInteger>(_ value: T) {
            var value = value.littleEndian
            withUnsafeBytes(of: &value) { wav.append(contentsOf: $0) }
        }
        word(UInt32(36 + 48000)); wav.append(Data("WAVEfmt ".utf8)); word(UInt32(16))
        word(UInt16(1)); word(UInt16(1)); word(UInt32(24000)); word(UInt32(48000))
        word(UInt16(2)); word(UInt16(16)); wav.append(Data("data".utf8)); word(UInt32(48000))
        wav.append(Data(repeating: 0, count: 48000))
        for take in 1...2 {
            let preparedAt = Date()
            let player = try ApprovedWAVPlayer(audio: wav)
            precondition(abs(player.duration - 1) < 0.001)
            precondition(player.timingDiagnostics["reusedWarmEngine"] == (take == 1 ? 0 : 1))
            let preparation = Date().timeIntervalSince(preparedAt)
            let started = Date()
            var result: Bool?
            player.completion = { result = $0 }
            precondition(player.play())
            try await Task.sleep(for: .milliseconds(350))
            precondition(player.currentTime > 0 && player.currentTime < player.duration)
            precondition(result == nil, "Played-back completion must not fire before the full WAV")
            for _ in 0..<200 {
                if result != nil { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            precondition(result == true && player.currentTime == player.duration)
            print("Silent take",take,"prepareMs",preparation * 1000,"requestToPlayedBackMs",Date().timeIntervalSince(started) * 1000)
            player.stop()
        }
        let cancelled = try ApprovedWAVPlayer(audio: wav)
        var callbacks = 0
        cancelled.completion = { _ in callbacks += 1 }
        precondition(cancelled.play())
        try await Task.sleep(for: .milliseconds(50))
        cancelled.stop()
        try await Task.sleep(for: .milliseconds(50))
        precondition(callbacks == 0, "Stopping must not report a successful natural completion")
        do { _ = try ApprovedWAVPlayer(audio: Data("invalid".utf8)); preconditionFailure("Invalid WAV must fail preparation") }
        catch { }
        let recovered = try ApprovedWAVPlayer(audio: wav)
        recovered.stop()
        // A different sample rate/channel layout must be reconfigured before
        // capture rather than changing pitch or reusing an incompatible graph.
        var stereo = wav
        func put<T: FixedWidthInteger>(_ value: T, at offset: Int) {
            var value = value.littleEndian
            withUnsafeBytes(of: &value) { stereo.replaceSubrange(offset..<(offset + $0.count), with: $0) }
        }
        put(UInt16(2), at: 22); put(UInt32(48000), at: 24)
        put(UInt32(192000), at: 28); put(UInt16(4), at: 32)
        let changedFormat = try ApprovedWAVPlayer(audio: stereo)
        precondition(abs(changedFormat.duration - 0.25) < 0.001)
        var changedResult: Bool?
        changedFormat.completion = { changedResult = $0 }
        precondition(changedFormat.play())
        for _ in 0..<200 {
            if changedResult != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(changedResult == true)
        changedFormat.stop()
        print("PASS: source-frame duration, real render clock, played-back completion, warm engine reuse, cancellation, format changes and invalid-file recovery; silence only, no recording")
    }
}
