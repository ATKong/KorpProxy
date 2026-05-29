import Foundation

/// A KorpProxy model selected for export into Factory's customModels.
///
/// Factory has no reasoning-effort picker for custom (BYOK) models, so we emit
/// one entry per reasoning level and encode the level as a `model(level)` suffix
/// (e.g. `claude-opus-4-8(high)`). KorpProxy's engine reads that suffix and
/// applies the thinking level regardless of what Factory sends.
struct ExportModel: Identifiable {
    let id = UUID()
    var include: Bool
    let modelID: String
    let displayName: String
    let isAnthropic: Bool
    let maxOutputTokens: Int
    let levels: [String]           // reasoning levels to emit; empty = one no-thinking entry
    let sourceLabel: String        // "Custom" or provider group (for the sheet)

    /// Number of Factory entries this model expands into.
    var entryCount: Int { max(1, levels.count) }
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

    /// One Factory customModel entry. `level == nil` emits a plain, no-thinking
    /// entry; otherwise the level is encoded as a `model(level)` suffix that the
    /// engine reads to set the reasoning effort.
    static func entry(_ m: ExportModel, level: String?, port: Int, apiKey: String) -> [String: Any] {
        let baseURL = m.isAnthropic ? "http://localhost:\(port)" : "http://localhost:\(port)/v1"
        let name = m.displayName.isEmpty ? m.modelID : m.displayName
        let modelField = level.map { "\(m.modelID)(\($0))" } ?? m.modelID
        let idSuffix = level.map { "-\($0)" } ?? ""
        let display = level.map { "KorpProxy: \(name) · \($0)" } ?? "KorpProxy: \(name)"
        var d: [String: Any] = [
            "model": modelField,
            "id": "custom:korpproxy:\(slug(m.modelID))\(idSuffix)",
            "baseUrl": baseURL,
            "apiKey": apiKey.isEmpty ? "dummy-not-used" : apiKey,
            "displayName": display,
            "enableThinking": level != nil,
            "maxOutputTokens": m.maxOutputTokens > 0 ? m.maxOutputTokens : 64000,
            "noImageSupport": false,
            "provider": m.isAnthropic ? "anthropic" : "openai",
        ]
        // Kept for when Factory adds native reasoning support for custom models;
        // today the engine derives the level from the model-name suffix instead.
        if let level { d["reasoningEffort"] = level }
        return d
    }

    /// All Factory entries for one model: one per reasoning level, or a single
    /// plain entry when the model has no levels.
    static func factoryEntries(_ m: ExportModel, port: Int, apiKey: String) -> [[String: Any]] {
        guard !m.levels.isEmpty else { return [entry(m, level: nil, port: port, apiKey: apiKey)] }
        return m.levels.map { entry(m, level: $0, port: port, apiKey: apiKey) }
    }

    /// Returns (modelCount, entryCount, backupURL).
    @discardableResult
    static func export(_ models: [ExportModel], port: Int, apiKey: String) throws -> (Int, Int, URL) {
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
        let added = selected.flatMap { factoryEntries($0, port: port, apiKey: apiKey) }
        entries.append(contentsOf: added)

        // Reindex for stable ordering.
        for i in entries.indices { entries[i]["index"] = i }
        root["customModels"] = entries

        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try out.write(to: url, options: .atomic)
        return (selected.count, added.count, backupURL)
    }

    private static func backupStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}
