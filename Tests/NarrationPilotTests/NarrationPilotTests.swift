import XCTest
@testable import NarrationPilot

final class NarrationPilotTests: XCTestCase {
    func testNotionSceneServiceTreatsEmptyNarrationAndOnScreenAsBlank() {
        XCTAssertTrue(NotionSceneService.isBlankScene(narration: "", onScreen: ""))
        XCTAssertTrue(NotionSceneService.isBlankScene(narration: "  \n", onScreen: "\t"))
    }

    func testNotionSceneServiceKeepsRowsWithEitherVisibleField() {
        XCTAssertFalse(NotionSceneService.isBlankScene(narration: "Explain this.", onScreen: ""))
        XCTAssertFalse(NotionSceneService.isBlankScene(narration: "", onScreen: "Show the editor."))
    }

    func testBaserowSceneServiceTreatsEmptyNarrationAndOnScreenAsBlank() {
        XCTAssertTrue(BaserowSceneService.isBlankScene(narration: "", onScreen: ""))
        XCTAssertTrue(BaserowSceneService.isBlankScene(narration: "  \n", onScreen: "\t"))
    }

    func testBaserowSceneServiceKeepsRowsWithEitherVisibleField() {
        XCTAssertFalse(BaserowSceneService.isBlankScene(narration: "Explain this.", onScreen: ""))
        XCTAssertFalse(BaserowSceneService.isBlankScene(narration: "", onScreen: "Show the editor."))
    }

    func testBaserowSceneServiceParsesLastEditedWithMicroseconds() {
        XCTAssertNotNil(BaserowSceneService.date(from: "2026-09-11T06:40:43.702896Z"))
    }

    func testBaserowSceneServiceParsesLastEditedWithoutFractionalSeconds() {
        XCTAssertNotNil(BaserowSceneService.date(from: "2026-09-11T06:40:43Z"))
    }

    func testOnScreenLinkExtractorFindsHTTPAndHTTPSLinksInOrder() {
        let urls = OnScreenLinkExtractor.urls(
            in: "Open https://github.com/Leonxlnx/unlazy and http://example.com/docs."
        )

        XCTAssertEqual(urls.map(\.absoluteString), [
            "https://github.com/Leonxlnx/unlazy",
            "http://example.com/docs"
        ])
    }

    func testOnScreenLinkExtractorRemovesDuplicateLinks() {
        let urls = OnScreenLinkExtractor.urls(
            in: "Use https://example.com twice: https://example.com"
        )

        XCTAssertEqual(urls.map(\.absoluteString), ["https://example.com"])
    }

    func testOnScreenLinkExtractorIgnoresUnsupportedSchemesAndPlainText() {
        let urls = OnScreenLinkExtractor.urls(
            in: "Email mailto:test@example.com or read example.com without a scheme."
        )

        XCTAssertTrue(urls.isEmpty)
    }

    func testSpeedMultiplierClamps() {
        XCTAssertEqual(SpeechRateMapper.clampMultiplier(0.1), 0.5)
        XCTAssertEqual(SpeechRateMapper.clampMultiplier(1.0), 1.0)
        XCTAssertEqual(SpeechRateMapper.clampMultiplier(2.2), 1.5)
    }

    func testUtteranceRateMapping() {
        let slow = SpeechRateMapper.utteranceRate(for: 0.5)
        let normal = SpeechRateMapper.utteranceRate(for: 1.0)
        let fast = SpeechRateMapper.utteranceRate(for: 1.5)

        XCTAssertLessThan(slow, normal)
        XCTAssertLessThan(normal, fast)
        XCTAssertGreaterThanOrEqual(slow, 0.1)
        XCTAssertLessThanOrEqual(fast, 1.0)
    }

    func testTriggerDelayClampsToSupportedRange() {
        XCTAssertEqual(AppModel.clampTriggerDelay(-0.5), 0)
        XCTAssertEqual(AppModel.clampTriggerDelay(1.0), 1.0)
        XCTAssertEqual(AppModel.clampTriggerDelay(2.5), 2.5)
        XCTAssertEqual(AppModel.clampTriggerDelay(12.0), 10.0)
    }

    func testRecordingCueDelaysClampToSupportedRanges() {
        XCTAssertEqual(AppModel.clampRecordingStartCueDelay(0), 0.1)
        XCTAssertEqual(AppModel.clampRecordingStartCueDelay(2), 1.0)
        XCTAssertEqual(AppModel.clampRecordingStopCueDelay(-1), 0)
        XCTAssertEqual(AppModel.clampRecordingStopCueDelay(2), 1.0)
    }

    func testNeonSpotlightBusySnapshotParses() {
        let snapshot = NeonSpotlightAnimationSnapshot(userInfo: [
            NeonSpotlightStatusProtocol.Key.protocolVersion: 1,
            NeonSpotlightStatusProtocol.Key.sessionIdentifier: "session-1",
            NeonSpotlightStatusProtocol.Key.state: "busy",
            NeonSpotlightStatusProtocol.Key.activeAnimationCount: 2,
            NeonSpotlightStatusProtocol.Key.requestIdentifier: "request-1",
            NeonSpotlightStatusProtocol.Key.reason: "requested",
        ])

        XCTAssertEqual(snapshot?.state, .busy)
        XCTAssertEqual(snapshot?.activeAnimationCount, 2)
        XCTAssertEqual(snapshot?.requestIdentifier, "request-1")
    }

    func testNeonSpotlightIdleSnapshotParses() {
        let snapshot = NeonSpotlightAnimationSnapshot(userInfo: [
            NeonSpotlightStatusProtocol.Key.protocolVersion: 1,
            NeonSpotlightStatusProtocol.Key.sessionIdentifier: "session-1",
            NeonSpotlightStatusProtocol.Key.state: "idle",
            NeonSpotlightStatusProtocol.Key.activeAnimationCount: 0,
            NeonSpotlightStatusProtocol.Key.reason: "activityChanged",
        ])

        XCTAssertEqual(snapshot?.state, .idle)
        XCTAssertEqual(snapshot?.reason, .activityChanged)
    }

    func testNeonSpotlightSnapshotRejectsUnknownProtocolVersion() {
        XCTAssertNil(NeonSpotlightAnimationSnapshot(userInfo: [
            NeonSpotlightStatusProtocol.Key.protocolVersion: 2,
            NeonSpotlightStatusProtocol.Key.sessionIdentifier: "session-1",
            NeonSpotlightStatusProtocol.Key.state: "idle",
            NeonSpotlightStatusProtocol.Key.activeAnimationCount: 0,
            NeonSpotlightStatusProtocol.Key.reason: "requested",
        ]))
    }

    func testNeonSpotlightSnapshotRejectsInconsistentStateAndCount() {
        XCTAssertNil(NeonSpotlightAnimationSnapshot(userInfo: [
            NeonSpotlightStatusProtocol.Key.protocolVersion: 1,
            NeonSpotlightStatusProtocol.Key.sessionIdentifier: "session-1",
            NeonSpotlightStatusProtocol.Key.state: "idle",
            NeonSpotlightStatusProtocol.Key.activeAnimationCount: 1,
            NeonSpotlightStatusProtocol.Key.reason: "requested",
        ]))
    }

    func testUserActivityIdlePeriodClampsToSafeRange() {
        XCTAssertEqual(UserActivityIdlePolicy.clampedIdlePeriod(0), 0.5)
        XCTAssertEqual(UserActivityIdlePolicy.clampedIdlePeriod(1), 1)
        XCTAssertEqual(UserActivityIdlePolicy.clampedIdlePeriod(8), 3)
    }

    func testUserActivityMaximumWaitClampsToSafeRange() {
        XCTAssertEqual(UserActivityIdlePolicy.clampedMaximumWait(0), 3)
        XCTAssertEqual(UserActivityIdlePolicy.clampedMaximumWait(10), 10)
        XCTAssertEqual(UserActivityIdlePolicy.clampedMaximumWait(90), 30)
    }

    func testFailureCueCanReuseSelectedStopSound() {
        XCTAssertEqual(
            RecordingFailureCueSound.sameAsStop.resolvedSound(stopSound: .glass),
            .glass
        )
    }

    func testClipboardNormalization() {
        let service = ClipboardService()
        XCTAssertEqual(service.normalize("   hello world\n"), "hello world")
    }

    func testChapterScriptClipboardTextUsesSelectedPartAndScriptTitle() {
        XCTAssertEqual(
            JSONSceneManagerView.chapterScriptClipboardText(
                part: "Chapter 2",
                scriptTitle: "JavaScript Local Storage Explained"
            ),
            "Chapter 2 - JavaScript Local Storage Explained"
        )
    }

    func testChapterScriptClipboardTextRequiresSpecificPartAndScriptTitle() {
        XCTAssertNil(JSONSceneManagerView.chapterScriptClipboardText(part: "", scriptTitle: "A Script"))
        XCTAssertNil(JSONSceneManagerView.chapterScriptClipboardText(part: "Chapter 1", scriptTitle: nil))
    }

    func testJSONSceneManagerSidebarWidthStaysWithinUsableBounds() {
        XCTAssertEqual(JSONSceneManagerView.clampedSidebarWidth(100, availableWidth: 960), 220)
        XCTAssertEqual(JSONSceneManagerView.clampedSidebarWidth(320, availableWidth: 960), 320)
        XCTAssertEqual(JSONSceneManagerView.clampedSidebarWidth(700, availableWidth: 960), 471)
    }

    func testScriptSceneSplitterSplitsSentences() {
        let scenes = ScriptSceneSplitter.scenes(from: "First step. Now click the button! Done?")
        XCTAssertEqual(scenes, ["First step.", "Now click the button!", "Done?"])
    }

    func testScriptSceneSplitterDropsEmptyWhitespace() {
        XCTAssertEqual(ScriptSceneSplitter.scenes(from: "\n\n  "), [])
    }

    func testNarrationChapterLoaderReadsVersionFive() throws {
        let data = Data(#"{"schemaVersion":5,"chapterNumber":1,"chapterTitle":"Test","scenes":[{"id":"scene-01","sceneNumber":1,"narration":"Hello.","onScreen":"Show the editor.","code":null,"annotation":"Make this clearer."}]}"#.utf8)
        let chapter = try NarrationChapterLoader.decode(data)
        XCTAssertEqual(chapter.schemaVersion, 5)
        XCTAssertEqual(chapter.scenes[0].onScreen, "Show the editor.")
        XCTAssertEqual(chapter.scenes[0].annotation, "Make this clearer.")
    }

    func testNarrationChapterLoaderMigratesVersionFour() throws {
        let data = Data(#"{"schemaVersion":4,"projectSlug":"test","chapterNumber":1,"chapterTitle":"Test","status":"draft","scenes":[{"id":"scene-01","sceneNumber":1,"sceneType":"action","title":"Run","displayTitle":"Run","onScreen":{"action":"Run the page.","result":"The page appears."},"narration":"Run it.","code":null,"links":[]}]}"#.utf8)
        let chapter = try NarrationChapterLoader.decode(data)
        XCTAssertEqual(chapter.schemaVersion, 5)
        XCTAssertEqual(chapter.scenes[0].onScreen, "Run the page.\nThe page appears.")
    }

    func testNarrationChapterLoaderRejectsDuplicateIDs() {
        let data = Data(#"{"schemaVersion":5,"chapterNumber":1,"chapterTitle":"Test","scenes":[{"id":"same","sceneNumber":1,"narration":"One.","onScreen":"One.","code":null},{"id":"same","sceneNumber":2,"narration":"Two.","onScreen":"Two.","code":null}]}"#.utf8)
        XCTAssertThrowsError(try NarrationChapterLoader.decode(data))
    }

    func testSpokenTextSanitizerRemovesBracketedDirections() {
        let text = "[On screen: Show the editor.] Yesterday, I wanted to add an image overlay."

        XCTAssertEqual(
            SpokenTextSanitizer.removingBracketedDirections(from: text),
            "Yesterday, I wanted to add an image overlay."
        )
    }

    func testSpokenTextSanitizerRemovesMultipleAndMultilineDirections() {
        let text = "First sentence. [On screen:\nShow the editor.] [Pause] Second sentence."

        XCTAssertEqual(
            SpokenTextSanitizer.removingBracketedDirections(from: text),
            "First sentence. Second sentence."
        )
    }

    func testSpokenTextSanitizerHandlesNestedBrackets() {
        let text = "Before [Show the editor [briefly] and close it] after."

        XCTAssertEqual(
            SpokenTextSanitizer.removingBracketedDirections(from: text),
            "Before after."
        )
    }

    func testSpokenTextSanitizerKeepsUnmatchedOpeningBracket() {
        let text = "Read this [unfinished direction"

        XCTAssertEqual(
            SpokenTextSanitizer.removingBracketedDirections(from: text),
            "Read this [unfinished direction"
        )
    }

    func testSpokenTextSanitizerCanReturnEmptyText() {
        XCTAssertEqual(
            SpokenTextSanitizer.removingBracketedDirections(from: " [Do not read this] "),
            ""
        )
    }

    func testSpeechPreparationPreservesBracketedDirectionsForReplay() {
        let text = " [On screen: Show the editor.] Read this sentence. "

        XCTAssertEqual(
            SpokenTextSanitizer.preparingForSpeech(text, includesBracketedDirections: true),
            "[On screen: Show the editor.] Read this sentence."
        )
    }

    func testSpeechPreparationRemovesBracketedDirectionsByDefault() {
        let text = "[On screen: Show the editor.] Read this sentence."

        XCTAssertEqual(
            SpokenTextSanitizer.preparingForSpeech(text, includesBracketedDirections: false),
            "Read this sentence."
        )
    }

    func testJSONSceneReplayReadsNarrationThenOnScreen() {
        let scene = NarrationScene(id: "scene-01", sceneNumber: 1, narration: "Explain it.", onScreen: "Show it.", code: nil)
        XCTAssertEqual(JSONSceneReplayFormatter.spokenText(for: scene), "Explain it.\nOn screen: Show it.")
    }

    func testPauseResumeLabel() {
        XCTAssertEqual(SpeechState.speaking.pauseResumeTitle, "Pause Reading")
        XCTAssertEqual(SpeechState.paused.pauseResumeTitle, "Resume Reading")
    }

    func testFocuSeeStateDetectsRecordingFromPauseAction() {
        let elements = [
            FocuSeeAccessibilityElementSnapshot(
                role: "AXButton",
                labels: ["Pause"],
                isEnabled: true
            )
        ]

        XCTAssertEqual(
            FocuSeeAccessibilityService.classify(isRunning: true, elements: elements),
            .recording
        )
    }

    func testFocuSeeStateDetectsPausedFromResumeAction() {
        let elements = [
            FocuSeeAccessibilityElementSnapshot(
                role: "AXMenuItem",
                labels: ["Resume"],
                isEnabled: true
            )
        ]

        XCTAssertEqual(
            FocuSeeAccessibilityService.classify(isRunning: true, elements: elements),
            .paused
        )
    }

    func testFocuSeeStateTreatsDisabledPauseControlAsNotRecording() {
        let elements = [
            FocuSeeAccessibilityElementSnapshot(
                role: "AXMenuItem",
                labels: ["Pause"],
                isEnabled: false
            )
        ]

        XCTAssertEqual(
            FocuSeeAccessibilityService.classify(isRunning: true, elements: elements),
            .notRecording
        )
    }

    func testFocuSeeStateFailsSafeWhenSignalsConflict() {
        let elements = [
            FocuSeeAccessibilityElementSnapshot(
                role: "AXButton",
                labels: ["Pause"],
                isEnabled: true
            ),
            FocuSeeAccessibilityElementSnapshot(
                role: "AXButton",
                labels: ["Resume"],
                isEnabled: true
            )
        ]

        XCTAssertEqual(
            FocuSeeAccessibilityService.classify(isRunning: true, elements: elements),
            .unknown
        )
    }

    func testFocuSeeStateDetectsClosedApplication() {
        XCTAssertEqual(
            FocuSeeAccessibilityService.classify(isRunning: false, elements: []),
            .notRunning
        )
    }
}
