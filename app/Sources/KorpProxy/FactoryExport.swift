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
    let fastEligible: Bool         // model supports a Fast/priority tier
    let sourceLabel: String        // "Custom" or provider group (for the sheet)

    /// Entries per reasoning level (Fast doubling is applied at export time).
    var baseEntryCount: Int { max(1, levels.count) }
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

    /// Whether a model supports a Fast / priority tier:
    /// - Claude: Opus 4.6 / 4.7 / 4.8 (`speed: "fast"`, per Anthropic Fast mode docs)
    /// - OpenAI/Codex: GPT-5.4 / 5.5 (`service_tier: "priority"`, per OpenAI Codex Speed docs)
    /// Sending fast to an unsupported model can error upstream, so we gate it.
    static func fastEligible(modelID: String, isAnthropic: Bool) -> Bool {
        let id = modelID.lowercased()
        if isAnthropic {
            return id.contains("opus-4-6") || id.contains("opus-4-7") || id.contains("opus-4-8")
        }
        return id.contains("gpt-5.4") || id.contains("gpt-5.5")
    }

    /// One Factory customModel entry. `level == nil` emits a plain, no-thinking
    /// entry; otherwise the level is encoded as a `model(level)` suffix that the
    /// engine reads to set the reasoning effort. `fast == true` adds the
    /// provider's Fast/priority tier via extraArgs.
    static func entry(_ m: ExportModel, level: String?, fast: Bool, port: Int, apiKey: String) -> [String: Any] {
        let baseURL = m.isAnthropic ? "http://localhost:\(port)" : "http://localhost:\(port)/v1"
        let name = m.displayName.isEmpty ? m.modelID : m.displayName
        let modelField = level.map { "\(m.modelID)(\($0))" } ?? m.modelID
        var idValue = "custom:korpproxy:\(slug(m.modelID))"
        if let level { idValue += "-\(level)" }
        if fast { idValue += "-fast" }
        var display = "KorpProxy: \(name)"
        if let level { display += " · \(level)" }
        if fast { display += " · fast" }
        var d: [String: Any] = [
            "model": modelField,
            "id": idValue,
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
        // Fast/priority tier. Claude uses the beta `speed` field (the engine already
        // sends the fast-mode beta header); OpenAI/Codex uses service_tier=priority.
        // Factory merges extraArgs into the request body.
        if fast {
            d["extraArgs"] = m.isAnthropic ? ["speed": "fast"] : ["service_tier": "priority"]
        }
        return d
    }

    /// All Factory entries for one model: one per reasoning level (plus a Fast
    /// twin for each when the model is fast-eligible and Fast is enabled).
    static func factoryEntries(_ m: ExportModel, includeFast: Bool, port: Int, apiKey: String) -> [[String: Any]] {
        let levels: [String?] = m.levels.isEmpty ? [nil] : m.levels.map { Optional($0) }
        var out: [[String: Any]] = []
        for level in levels {
            out.append(entry(m, level: level, fast: false, port: port, apiKey: apiKey))
            if includeFast && m.fastEligible {
                out.append(entry(m, level: level, fast: true, port: port, apiKey: apiKey))
            }
        }
        return out
    }

    /// Returns (modelCount, entryCount, backupURL).
    @discardableResult
    static func export(_ models: [ExportModel], includeFast: Bool, port: Int, apiKey: String) throws -> (Int, Int, URL) {
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
        let added = selected.flatMap { factoryEntries($0, includeFast: includeFast, port: port, apiKey: apiKey) }
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
