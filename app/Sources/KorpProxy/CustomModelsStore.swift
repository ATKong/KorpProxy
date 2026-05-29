import Foundation
import Observation

/// A user-added model that KorpProxy injects into the engine's catalog so a
/// brand-new cloud model can be served before upstream's models.json lists it.
struct CustomModel: Codable, Identifiable, Sendable, Hashable {
    var uuid: UUID = UUID()
    var modelID: String           // e.g. "claude-opus-4-9"
    var provider: String          // catalog section key, e.g. "claude"
    var displayName: String = ""
    var type: String = ""         // routing type: "claude" / "gemini" / "openai" / …
    var ownedBy: String = ""
    var contextLength: Int = 0
    var maxCompletionTokens: Int = 0
    var modelDescription: String = ""

    var id: UUID { uuid }

    enum CodingKeys: String, CodingKey {
        case uuid, modelID, provider, displayName, type, ownedBy
        case contextLength, maxCompletionTokens, modelDescription
    }

    init(modelID: String, provider: String) {
        self.modelID = modelID
        self.provider = provider
        self.type = ModelProvider.find(provider)?.defaultType ?? ""
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uuid = (try? c.decode(UUID.self, forKey: .uuid)) ?? UUID()
        modelID = try c.decode(String.self, forKey: .modelID)
        provider = try c.decode(String.self, forKey: .provider)
        displayName = (try? c.decode(String.self, forKey: .displayName)) ?? ""
        type = (try? c.decode(String.self, forKey: .type)) ?? ""
        ownedBy = (try? c.decode(String.self, forKey: .ownedBy)) ?? ""
        contextLength = (try? c.decode(Int.self, forKey: .contextLength)) ?? 0
        maxCompletionTokens = (try? c.decode(Int.self, forKey: .maxCompletionTokens)) ?? 0
        modelDescription = (try? c.decode(String.self, forKey: .modelDescription)) ?? ""
    }

    /// The catalog entry (matches the engine's ModelInfo JSON keys).
    func catalogEntry() -> [String: Any] {
        var d: [String: Any] = [
            "id": modelID,
            "object": "model",
            "created": Int(Date().timeIntervalSince1970),
            "type": type.isEmpty ? (ModelProvider.find(provider)?.defaultType ?? "openai") : type,
        ]
        if !ownedBy.isEmpty { d["owned_by"] = ownedBy }
        if !displayName.isEmpty { d["display_name"] = displayName }
        if !modelDescription.isEmpty { d["description"] = modelDescription }
        if contextLength > 0 { d["context_length"] = contextLength }
        if maxCompletionTokens > 0 { d["max_completion_tokens"] = maxCompletionTokens }
        return d
    }
}

/// A catalog section the engine recognises (keys mirror staticModelsJSON).
struct ModelProvider: Identifiable, Hashable {
    let key: String
    let label: String
    let defaultType: String
    var id: String { key }

    static let all: [ModelProvider] = [
        .init(key: "claude", label: "Claude", defaultType: "claude"),
        .init(key: "gemini", label: "Gemini", defaultType: "gemini"),
        .init(key: "vertex", label: "Gemini (Vertex)", defaultType: "gemini"),
        .init(key: "gemini-cli", label: "Gemini CLI", defaultType: "gemini"),
        .init(key: "aistudio", label: "AI Studio", defaultType: "gemini"),
        .init(key: "codex-free", label: "Codex (Free)", defaultType: "openai"),
        .init(key: "codex-team", label: "Codex (Team)", defaultType: "openai"),
        .init(key: "codex-plus", label: "Codex (Plus)", defaultType: "openai"),
        .init(key: "codex-pro", label: "Codex (Pro)", defaultType: "openai"),
        .init(key: "kimi", label: "Kimi", defaultType: "kimi"),
        .init(key: "antigravity", label: "Antigravity", defaultType: "antigravity"),
        .init(key: "xai", label: "xAI (Grok)", defaultType: "xai"),
    ]

    static func find(_ key: String) -> ModelProvider? { all.first { $0.key == key } }
    static func label(_ key: String) -> String { find(key)?.label ?? key }
}

/// Persists user-added models to `custom-models.json` and notifies a listener
/// (the local catalog server) whenever the set changes.
@Observable
final class CustomModelsStore {
    private(set) var models: [CustomModel] = []

    @ObservationIgnored private let fileURL: URL
    /// Invoked after every save with the latest snapshot (wired to the server).
    @ObservationIgnored var onChange: (([CustomModel]) -> Void)?

    init(baseDir: URL) {
        fileURL = baseDir.appendingPathComponent("custom-models.json")
        load()
    }

    func add(_ model: CustomModel) {
        if let idx = models.firstIndex(where: { $0.uuid == model.uuid }) {
            models[idx] = model
        } else {
            models.append(model)
        }
        save()
    }

    func remove(_ model: CustomModel) {
        models.removeAll { $0.uuid == model.uuid }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([CustomModel].self, from: data) else { return }
        models = decoded
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(models) {
            try? data.write(to: fileURL, options: .atomic)
        }
        onChange?(models)
    }
}

/// Merges user-added models onto a base catalog (the live upstream models.json).
/// The engine replaces its whole catalog with the first valid source, so we must
/// serve "upstream + additions", not just the additions.
enum ModelCatalogMerger {
    static func merged(base: Data, custom: [CustomModel]) -> Data {
        guard var root = (try? JSONSerialization.jsonObject(with: base)) as? [String: Any] else {
            return base
        }
        for model in custom where !model.modelID.isEmpty {
            let key = model.provider
            var section = (root[key] as? [[String: Any]]) ?? []
            let entry = model.catalogEntry()
            if let idx = section.firstIndex(where: { ($0["id"] as? String) == model.modelID }) {
                section[idx] = entry   // override an existing id
            } else {
                section.append(entry)
            }
            root[key] = section
        }
        return (try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])) ?? base
    }
}
