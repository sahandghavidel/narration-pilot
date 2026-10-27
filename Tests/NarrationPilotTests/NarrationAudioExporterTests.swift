import XCTest
@testable import NarrationPilot

final class NarrationAudioExporterTests: XCTestCase {
    func testExportTextKeepsSelectionOrderAndOmitsDirectionsAndEmptyScenes() {
        XCTAssertEqual(
            NarrationAudioExporter.spokenSegments(["First [show editor] scene", "[pause]", "  ", "Last scene"]),
            ["First scene", "Last scene"]
        )
    }

    func testDurationCoversWholePartAndRespondsToSpeed() {
        let texts = [String(repeating: "word ", count: 175), String(repeating: "word ", count: 175)]
        XCTAssertEqual(NarrationAudioExporter.estimatedDuration(texts: texts, speed: 1), 120, accuracy: 0.01)
        XCTAssertEqual(NarrationAudioExporter.estimatedDuration(texts: texts, speed: 2), 60, accuracy: 0.01)
        XCTAssertEqual(NarrationAudioExporter.estimatedDuration(texts: ["[pause]", ""], speed: 1), 0)
    }
}
