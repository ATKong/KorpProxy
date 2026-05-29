import Foundation
import Observation

/// One model the engine currently serves (from GET /v1/models).
struct ServedModel: Decodable, Identifiable, Hashable {
    let id: String
    let ownedBy: String?
    let created: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case ownedBy = "owned_by"
        case created
    }
}

/// Served models bucketed under a friendly provider label.
struct ProviderGroup: Identifiable {
    let provider: String
    let models: [ServedModel]
    var id: String { provider }
}

/// Fetches the live model list the engine serves for the user's logged-in
/// accounts (and API keys), grouped by provider. Read-only.
@MainActor
@Observable
final class AvailableModelsModel {
    private(set) var groups: [ProviderGroup] = []
    private(set) var total = 0
    private(set) var loading = false
    var errorMessage: String?

    @ObservationIgnored private var port = 8417
    @ObservationIgnored private var apiKey = ""

    func configure(port: Int, apiKey: String) {
        self.port = port
        self.apiKey = apiKey
    }

    func refresh() async {
        guard !apiKey.isEmpty, let url = URL(string: "http://127.0.0.1:\(port)/v1/models") else {
            errorMessage = "No API key configured."
            return
        }
        loading = true
        defer { loading = false }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 8
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else {
                errorMessage = "Engine returned HTTP \(code)."
                groups = []; total = 0
                return
            }
            let decoded = try JSONDecoder().decode(ModelsList.self, from: data)
            errorMessage = nil
            total = decoded.data.count
            groups = Self.group(decoded.data)
        } catch {
            errorMessage = error.localizedDescription
            groups = []; total = 0
        }
    }

    private struct ModelsList: Decodable { let data: [ServedModel] }

    /// Map a model to a friendly provider label using owned_by, then id prefix.
    static func providerLabel(ownedBy: String?, id: String) -> String {
        let owner = (ownedBy ?? "").lowercased()
        let mid = id.lowercased()
        if owner.contains("anthropic") || mid.hasPrefix("claude") { return "Claude" }
        if owner.contains("google") || mid.hasPrefix("gemini") || mid.hasPrefix("imagen") { return "Gemini" }
        if owner.contains("openai") || mid.hasPrefix("gpt") || mid.hasPrefix("o1")
            || mid.hasPrefix("o3") || mid.hasPrefix("o4") || mid.contains("codex") { return "OpenAI / Codex" }
        if owner.contains("moonshot") || mid.hasPrefix("kimi") { return "Kimi" }
        if owner.contains("x-ai") || owner.contains("xai") || mid.hasPrefix("grok") { return "xAI" }
        if !owner.isEmpty { return owner.capitalized }
        return "Other"
    }

    static func group(_ models: [ServedModel]) -> [ProviderGroup] {
        var buckets: [String: [ServedModel]] = [:]
        for model in models {
            buckets[providerLabel(ownedBy: model.ownedBy, id: model.id), default: []].append(model)
        }
        return buckets
            .map { ProviderGroup(provider: $0.key, models: $0.value.sorted { $0.id < $1.id }) }
            .sorted { $0.provider < $1.provider }
    }
}
