import Foundation

/// One entry from Factory's `~/.factory/settings.json` → `customModels[]`.
struct FactoryCustomModel: Decodable {
    let model: String
    let id: String?
    let displayName: String?
    let provider: String?
    let baseUrl: String?
    let maxOutputTokens: Int?
    let reasoningEffort: String?
    let enableThinking: Bool?
}

/// Reads Factory's custom-model definitions and maps them onto KorpProxy
/// `CustomModel`s (including a discrete thinking ladder from reasoningEffort).
enum FactoryImport {
    enum ImportError: LocalizedError {
        case notFound(String)
        case empty
        var errorDescription: String? {
            switch self {
            case .notFound(let path): return "No Factory settings found at \(path)."
            case .empty: return "Factory settings has no customModels to import."
            }
        }
    }

    static func settingsURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".factory/settings.json")
    }

    static func loadFactoryModels() throws -> [FactoryCustomModel] {
        let url = settingsURL()
        guard let data = try? Data(contentsOf: url) else {
            throw ImportError.notFound(url.path)
        }
        struct Root: Decodable { let customModels: [FactoryCustomModel]? }
        let root = try JSONDecoder().decode(Root.self, from: data)
        let models = root.customModels ?? []
        if models.isEmpty { throw ImportError.empty }
        return models
    }

    /// Map a Factory custom model to a KorpProxy CustomModel.
    static func toCustomModel(_ f: FactoryCustomModel) -> CustomModel {
        let section = sectionKey(model: f.model, displayName: f.displayName, factoryProvider: f.provider)
        var m = CustomModel(modelID: f.model, provider: section)
        m.displayName = f.displayName ?? ""
        m.maxCompletionTokens = f.maxOutputTokens ?? 0
        m.ownedBy = f.provider ?? ""
        if (f.enableThinking ?? false), let effort = f.reasoningEffort, !effort.isEmpty {
            m.thinkingLevels = CustomModel.levels(upTo: effort)
        }
        return m
    }

    /// Best-effort mapping to a KorpProxy catalog section. The user can adjust
    /// any model afterwards in the editor.
    static func sectionKey(model: String, displayName: String?, factoryProvider: String?) -> String {
        let dn = (displayName ?? "").lowercased()
        if dn.contains("antigravity") { return "antigravity" }
        let m = model.lowercased()
        if m.hasPrefix("claude") { return "claude" }
        if m.hasPrefix("gemini") { return "gemini" }
        if m.hasPrefix("kimi") { return "kimi" }
        if m.hasPrefix("grok") { return "xai" }
        if m.hasPrefix("gpt") || m.contains("codex") || m.contains("oss") || m.hasPrefix("cursor") {
            return "codex-pro"
        }
        switch (factoryProvider ?? "").lowercased() {
        case "anthropic": return "claude"
        default: return "codex-pro"
        }
    }
}
