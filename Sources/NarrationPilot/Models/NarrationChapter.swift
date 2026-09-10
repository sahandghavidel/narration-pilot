import Foundation

enum ScriptInputFormat: String, CaseIterable, Identifiable {
    case text, json, baserow
    var id: String { rawValue }
    var label: String {
        switch self {
        case .text: "Text Script"
        case .json: "Notion Scenes"
        case .baserow: "Baserow Scenes"
        }
    }

    var usesStructuredScenes: Bool { self != .text }
}

struct NarrationChapter: Codable, Equatable {
    let schemaVersion: Int
    let chapterNumber: Int
    let chapterTitle: String
    let scenes: [NarrationScene]
}

struct NarrationScene: Codable, Equatable, Identifiable {
    let id: String
    let sceneNumber: Int
    let narration: String
    let onScreen: String
    let code: NarrationCode?
    var annotation: String? = nil
}

struct NarrationCode: Codable, Equatable {
    let text: String
    let language: String
    let targetFile: String
    let action: NarrationCodeAction
    var instruction: String? = nil
}

enum NarrationCodeAction: String, Codable, CaseIterable { case create, replace, append, insert }

enum NarrationChapterLoader {
    static let supportedSchemaVersion = 5
    static let readableSchemaVersions = [2, 3, 4, 5]

    static func load(from url: URL) throws -> NarrationChapter { try decode(Data(contentsOf: url)) }

    static func decode(_ data: Data) throws -> NarrationChapter {
        let version = try schemaVersion(in: data)
        let chapter: NarrationChapter
        do {
            switch version {
            case 5: chapter = try JSONDecoder().decode(NarrationChapter.self, from: data)
            case 4: chapter = migrate(try JSONDecoder().decode(LegacyNarrationChapterV4.self, from: data))
            case 3: chapter = migrate(try JSONDecoder().decode(LegacyNarrationChapterV3.self, from: data))
            case 2: chapter = migrate(try JSONDecoder().decode(LegacyNarrationChapterV2.self, from: data))
            default: throw NarrationChapterError.unsupportedSchemaVersion(version)
            }
        } catch let error as NarrationChapterError { throw error }
        catch { throw NarrationChapterError.invalidJSON(error.localizedDescription) }
        try validate(chapter)
        return chapter
    }

    static func validate(_ chapter: NarrationChapter) throws {
        guard chapter.schemaVersion == supportedSchemaVersion else { throw NarrationChapterError.unsupportedSchemaVersion(chapter.schemaVersion) }
        guard chapter.chapterNumber > 0 else { throw NarrationChapterError.invalidChapterNumber }
        guard !chapter.chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw NarrationChapterError.missingChapterTitle }
        guard !chapter.scenes.isEmpty else { throw NarrationChapterError.noScenes }
        var sceneIDs = Set<String>()
        for (index, scene) in chapter.scenes.enumerated() {
            guard scene.sceneNumber == index + 1 else { throw NarrationChapterError.invalidSceneNumber(expected: index + 1, actual: scene.sceneNumber) }
            let id = scene.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { throw NarrationChapterError.missingSceneID(scene.sceneNumber) }
            guard sceneIDs.insert(id).inserted else { throw NarrationChapterError.duplicateSceneID(id) }
            guard !scene.narration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw NarrationChapterError.emptyNarration(scene.sceneNumber) }
            guard !scene.onScreen.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw NarrationChapterError.emptyOnScreenResult(scene.sceneNumber) }
            if let code = scene.code {
                guard !code.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !code.language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !code.targetFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw NarrationChapterError.invalidCode(scene.sceneNumber) }
            }
        }
    }

    private static func schemaVersion(in data: Data) throws -> Int {
        do {
            let object = try JSONSerialization.jsonObject(with: data)
            guard let dictionary = object as? [String: Any], let version = dictionary["schemaVersion"] as? Int else {
                throw NarrationChapterError.invalidJSON("schemaVersion is missing or invalid.")
            }
            return version
        } catch let error as NarrationChapterError { throw error }
        catch { throw NarrationChapterError.invalidJSON(error.localizedDescription) }
    }

    private static func combinedOnScreen(action: String?, result: String) -> String {
        [action, result].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private static func migrate(_ legacy: LegacyNarrationChapterV4) -> NarrationChapter {
        NarrationChapter(schemaVersion: 5, chapterNumber: legacy.chapterNumber, chapterTitle: legacy.chapterTitle, scenes: legacy.scenes.map { scene in
            NarrationScene(id: scene.id, sceneNumber: scene.sceneNumber, narration: scene.narration,
                           onScreen: combinedOnScreen(action: scene.onScreen.action, result: scene.onScreen.result), code: scene.code,
                           annotation: scene.annotation)
        })
    }

    private static func migrate(_ legacy: LegacyNarrationChapterV3) -> NarrationChapter {
        NarrationChapter(schemaVersion: 5, chapterNumber: legacy.chapterNumber, chapterTitle: legacy.chapterTitle, scenes: legacy.scenes.map { scene in
            NarrationScene(id: scene.id, sceneNumber: scene.sceneNumber, narration: scene.narration,
                           onScreen: combinedOnScreen(action: scene.onScreen.action, result: scene.onScreen.result), code: scene.code)
        })
    }

    private static func migrate(_ legacy: LegacyNarrationChapterV2) -> NarrationChapter {
        NarrationChapter(schemaVersion: 5, chapterNumber: legacy.chapterNumber, chapterTitle: legacy.chapterTitle, scenes: legacy.scenes.map { scene in
            NarrationScene(id: scene.id, sceneNumber: scene.sceneNumber, narration: scene.narration,
                           onScreen: combinedOnScreen(action: scene.onScreen.action, result: scene.onScreen.result),
                           code: scene.code.map { NarrationCode(text: $0, language: "text", targetFile: "Unspecified", action: .insert) })
        })
    }
}

extension JSONEncoder {
    static var narrationPilot: JSONEncoder {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder
    }
}

private struct LegacyNarrationChapterV4: Codable { let chapterNumber: Int; let chapterTitle: String; let scenes: [LegacyNarrationSceneV4] }
private struct LegacyNarrationSceneV4: Codable {
    let id: String; let sceneNumber: Int; let narration: String; let onScreen: LegacyNarrationOnScreen
    let code: NarrationCode?; let visualId: String?; let annotation: String?
}
private struct LegacyNarrationChapterV3: Codable { let chapterNumber: Int; let chapterTitle: String; let scenes: [LegacyNarrationSceneV3] }
private struct LegacyNarrationSceneV3: Codable { let id: String; let sceneNumber: Int; let onScreen: LegacyNarrationOnScreen; let narration: String; let code: NarrationCode? }
private struct LegacyNarrationChapterV2: Codable { let chapterNumber: Int; let chapterTitle: String; let scenes: [LegacyNarrationSceneV2] }
private struct LegacyNarrationSceneV2: Codable { let id: String; let sceneNumber: Int; let onScreen: LegacyNarrationOnScreen; let narration: String; let code: String? }
private struct LegacyNarrationOnScreen: Codable { let action: String?; let result: String }

enum NarrationChapterError: LocalizedError, Equatable {
    case invalidJSON(String), unsupportedSchemaVersion(Int), invalidChapterNumber, missingChapterTitle, noScenes
    case invalidSceneNumber(expected: Int, actual: Int), missingSceneID(Int), duplicateSceneID(String)
    case emptyNarration(Int), emptyOnScreenResult(Int), invalidCode(Int)

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let message): "Invalid chapter JSON: \(message)"
        case .unsupportedSchemaVersion(let version): "Unsupported schema version \(version). Narration Pilot reads versions \(NarrationChapterLoader.readableSchemaVersions.map(String.init).joined(separator: ", "))."
        case .invalidChapterNumber: "chapterNumber must be greater than zero."
        case .missingChapterTitle: "The chapter is missing chapterTitle."
        case .noScenes: "The chapter must contain at least one scene."
        case .invalidSceneNumber(let expected, let actual): "Scene numbers must be sequential. Expected \(expected), found \(actual)."
        case .missingSceneID(let number): "Scene \(number) is missing an id."
        case .duplicateSceneID(let id): "The scene id \(id) is used more than once."
        case .emptyNarration(let number): "Scene \(number) has empty narration."
        case .emptyOnScreenResult(let number): "Scene \(number) has empty onScreen text."
        case .invalidCode(let number): "Scene \(number) has incomplete structured code."
        }
    }
}
