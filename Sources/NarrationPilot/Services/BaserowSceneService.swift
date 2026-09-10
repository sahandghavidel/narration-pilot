import Foundation
import Security

struct BaserowSceneRecord: Equatable {
    let rowID: Int
    let lastEditedTime: String
    let scene: NarrationScene
}

enum BaserowSceneError: LocalizedError {
    case invalidURL
    case invalidResponse
    case api(String)
    case invalidScenes(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Enter a valid Baserow base URL."
        case .invalidResponse: "Baserow returned an invalid response."
        case .api(let message): message
        case .invalidScenes(let message): message
        }
    }
}

@MainActor
final class BaserowSceneService {
    func fetchScenes(baseURL: String, token: String, tableID: String) async throws -> [BaserowSceneRecord] {
        var records: [BaserowSceneRecord] = []
        var page = 1

        while true {
            let result = try await request(
                baseURL: baseURL,
                path: "/api/database/rows/table/\(clean(tableID))/",
                method: "GET",
                token: token,
                queryItems: [
                    URLQueryItem(name: "user_field_names", value: "true"),
                    URLQueryItem(name: "size", value: "200"),
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "order_by", value: "Scene Number")
                ]
            )
            guard let rows = result["results"] as? [[String: Any]] else {
                throw BaserowSceneError.invalidResponse
            }
            records.append(contentsOf: try rows.compactMap(record(from:)))
            guard result["next"] is String else { break }
            page += 1
        }

        return records.sorted { $0.scene.sceneNumber < $1.scene.sceneNumber }
    }

    func updateScene(
        _ scene: NarrationScene,
        rowID: Int,
        baseURL: String,
        token: String,
        tableID: String
    ) async throws {
        let code = scene.code
        let fields: [String: Any] = [
            "Scene Number": scene.sceneNumber,
            "Narration": scene.narration,
            "On Screen": scene.onScreen,
            "Annotation": scene.annotation ?? "",
            "Code": code?.text ?? "",
            "Language": code?.language ?? "",
            "Target File": code?.targetFile ?? "",
            "Code Instruction": code?.instruction ?? ""
        ]
        _ = try await request(
            baseURL: baseURL,
            path: "/api/database/rows/table/\(clean(tableID))/\(rowID)/",
            method: "PATCH",
            token: token,
            queryItems: [URLQueryItem(name: "user_field_names", value: "true")],
            body: fields
        )
    }

    static func isBlankScene(narration: String, onScreen: String) -> Bool {
        narration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && onScreen.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func record(from row: [String: Any]) throws -> BaserowSceneRecord? {
        guard let rowID = integer(row["id"]) else { throw BaserowSceneError.invalidResponse }
        let narration = string(row["Narration"])
        let onScreen = string(row["On Screen"])
        if Self.isBlankScene(narration: narration, onScreen: onScreen) { return nil }

        guard let sceneNumber = integer(row["Scene Number"]), sceneNumber > 0 else {
            throw BaserowSceneError.invalidScenes("A Baserow row is missing a valid Scene Number.")
        }

        let codeText = string(row["Code"])
        let code: NarrationCode?
        if codeText.isEmpty {
            code = nil
        } else {
            let language = string(row["Language"])
            let targetFile = string(row["Target File"])
            let instruction = string(row["Code Instruction"])
            guard !language.isEmpty, !targetFile.isEmpty else {
                throw BaserowSceneError.invalidScenes("Scene \(sceneNumber) code needs Language and Target File values.")
            }
            code = NarrationCode(
                text: codeText,
                language: language,
                targetFile: targetFile,
                action: inferredAction(from: instruction),
                instruction: instruction.isEmpty ? nil : instruction
            )
        }

        guard !narration.isEmpty, !onScreen.isEmpty else {
            throw BaserowSceneError.invalidScenes("Scene \(sceneNumber) needs Narration and On Screen values.")
        }

        return BaserowSceneRecord(
            rowID: rowID,
            lastEditedTime: string(row["Last Edited"]),
            scene: NarrationScene(
                id: "baserow-row-\(rowID)",
                sceneNumber: sceneNumber,
                narration: narration,
                onScreen: onScreen,
                code: code,
                annotation: nilIfEmpty(string(row["Annotation"]))
            )
        )
    }

    private func request(
        baseURL: String,
        path: String,
        method: String,
        token: String,
        queryItems: [URLQueryItem],
        body: [String: Any]? = nil
    ) async throws -> [String: Any] {
        let trimmedBaseURL = clean(baseURL).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(string: trimmedBaseURL + path) else {
            throw BaserowSceneError.invalidURL
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw BaserowSceneError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Token \(clean(token))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BaserowSceneError.invalidResponse }
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(http.statusCode) else {
            let detail = object["detail"] as? String
            let error = object["error"] as? String
            throw BaserowSceneError.api(detail ?? error ?? "Baserow request failed (\(http.statusCode)).")
        }
        return object
    }

    static func date(from value: String) -> Date? {
        guard !value.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private func string(_ value: Any?) -> String {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return ""
    }

    private func inferredAction(from instruction: String) -> NarrationCodeAction {
        let value = instruction.lowercased()
        if value.hasPrefix("replace") { return .replace }
        if value.hasPrefix("append") { return .append }
        if value.hasPrefix("create") { return .create }
        return .insert
    }

    private func nilIfEmpty(_ value: String) -> String? { value.isEmpty ? nil : value }
    private func clean(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
}

enum BaserowTokenStore {
    private static let service = "local.clipboardreadermac.baserow"
    private static let account = "database-token"

    static func load() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func save(_ token: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        guard !token.isEmpty else { return }
        var item = base
        item[kSecValueData as String] = Data(token.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }
}
