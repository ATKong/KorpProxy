import Foundation

/// A KorpProxy model selected for export into Factory's customModels.
struct ExportModel: Identifiable {
    let id = UUID()
    var include: Bool
    let modelID: String
    let displayName: String
    let isAnthropic: Bool
    let maxOutputTokens: Int
    let reasoningEffort: String?   // nil = no thinking
    let sourceLabel: String        // "Custom" or provider group (for the sheet)
}

/// Writes selected KorpProxy models into ~/.factory/settings.json → customModels,
/// pointed at the local KorpProxy server. Existing non-KorpProxy entries are kept;
/// any prior KorpProxy entries are replaced so re-export stays idempotent. The
/// current settings file is backed up first.
enum FactoryExport {
    enum ExportError: LocalizedError {
        case notFound(String)
        case unreadable(String)
        var errorDescription: String? {
            switch self {
            case .notFound(let p): return "No Factory settings found at \(p)."
            case .unreadable(let p): return "Couldn’t read Factory settings at \(p)."
            }
        }
    }

    static func settingsURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".factory/settings.json")
    }

    static func slug(_ s: String) -> String {
        let mapped = s.lowercased().map { ($0.isLetter || $0.isNumber) ? $0 : "-" }
        var out = String(mapped)
        while out.contains("--") { out = out.replacingOccurrences(of: "--", with: "-") }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    static func entry(_ m: ExportModel, port: Int, apiKey: String) -> [String: Any] {
        let baseURL = m.isAnthropic ? "http://localhost:\(port)" : "http://localhost:\(port)/v1"
        let name = m.displayName.isEmpty ? m.modelID : m.displayName
        return [
            "model": m.modelID,
            "id": "custom:korpproxy:\(slug(m.modelID))",
            "baseUrl": baseURL,
            "apiKey": apiKey.isEmpty ? "dummy-not-used" : apiKey,
            "displayName": "KorpProxy: \(name)",
            "enableThinking": m.reasoningEffort != nil,
            "maxOutputTokens": m.maxOutputTokens > 0 ? m.maxOutputTokens : 64000,
            "reasoningEffort": m.reasoningEffort ?? "high",
            "noImageSupport": false,
            "provider": m.isAnthropic ? "anthropic" : "openai",
        ]
    }

    /// Returns (exportedCount, backupURL).
    @discardableResult
    static func export(_ models: [ExportModel], port: Int, apiKey: String) throws -> (Int, URL) {
        let url = settingsURL()
        guard let data = try? Data(contentsOf: url) else { throw ExportError.notFound(url.path) }
        guard var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ExportError.unreadable(url.path)
        }

        // Back up the current settings first.
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent("settings.json.korpproxy-\(backupStamp()).bak")
        try? data.write(to: backupURL)

        // Keep existing non-KorpProxy entries; replace any prior KorpProxy ones.
        var entries = (root["customModels"] as? [[String: Any]]) ?? []
        entries.removeAll { ($0["id"] as? String)?.hasPrefix("custom:korpproxy:") == true }

        let selected = models.filter(\.include)
        entries.append(contentsOf: selected.map { entry($0, port: port, apiKey: apiKey) })

        // Reindex for stable ordering.
        for i in entries.indices { entries[i]["index"] = i }
        root["customModels"] = entries

        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try out.write(to: url, options: .atomic)
        return (selected.count, backupURL)
    }

    private static func backupStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}
