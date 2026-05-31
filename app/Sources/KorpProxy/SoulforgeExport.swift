import Foundation

/// Writes selected KorpProxy models into ~/.soulforge/config.json as a single
/// custom provider (`providers[]`), pointed at the local KorpProxy server's
/// OpenAI-compatible endpoint. SoulForge custom providers are OpenAI-compatible,
/// so every model — including Claude — is served through `/v1/chat/completions`
/// (the engine translates per upstream).
///
/// Existing providers are preserved; any prior "korpproxy" provider is replaced
/// so re-export stays idempotent. The current config is backed up first, and the
/// file (and ~/.soulforge) is created when it doesn't exist yet.
enum SoulforgeExport {
    /// Provider id used in SoulForge model strings (e.g. `korpproxy/claude-opus-4-8`)
    /// and with `soulforge --set-key korpproxy <key>`.
    static let providerID = "korpproxy"
    /// Env var SoulForge reads the key from when the keystore has no entry.
    static let envVar = "KORPPROXY_API_KEY"

    enum ExportError: LocalizedError {
        case unreadable(String)
        var errorDescription: String? {
            switch self {
            case .unreadable(let p): return "Couldn’t read SoulForge config at \(p)."
            }
        }
    }

    static func configURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".soulforge/config.json")
    }

    /// The command that registers KorpProxy's API key with SoulForge.
    static func setKeyCommand(apiKey: String) -> String {
        "soulforge --set-key \(providerID) \(apiKey.isEmpty ? "<your-korpproxy-api-key>" : apiKey)"
    }

    /// One entry for the provider's `models` array: `{ id, name, thinking? }`.
    /// Unlike Factory, SoulForge has no per-model reasoning picker, so we emit
    /// the model's discrete reasoning levels as `thinking.levels` here — that's
    /// the effort ladder SoulForge offers when the model is used.
    ///
    /// `fast == true` emits the priority/speed-tier twin: SoulForge has no Fast
    /// picker for custom providers, so we expose a separate `<model>-fast` id.
    /// The engine maps that suffix to `service_tier: "priority"` upstream.
    static func modelEntry(_ m: ExportModel, fast: Bool = false) -> [String: Any] {
        let baseName = m.displayName.isEmpty ? m.modelID : m.displayName
        var entry: [String: Any] = [
            "id": "\(m.modelID)\(fast ? "-fast" : "")",
            "name": "\(baseName)\(fast ? " · fast" : "")",
        ]
        if !m.thinkingLevels.isEmpty {
            entry["thinking"] = ["levels": m.thinkingLevels]
        }
        return entry
    }

    /// Whether a model gets a Fast twin in the SoulForge export. Scoped to
    /// OpenAI/Codex GPT models — only the Codex path honours the `-fast`
    /// suffix (`service_tier: "priority"`); Claude Fast is not wired here.
    static func fastEligible(_ m: ExportModel) -> Bool {
        !m.isAnthropic && m.fastEligible
    }

    /// SoulForge model entries for one model: the standard entry, plus a Fast
    /// twin when the model is eligible and the user selected Fast.
    static func modelEntries(_ m: ExportModel) -> [[String: Any]] {
        var out: [[String: Any]] = [modelEntry(m)]
        if m.includeFast && fastEligible(m) {
            out.append(modelEntry(m, fast: true))
        }
        return out
    }

    /// The `korpproxy` provider block for SoulForge's `providers` array.
    static func providerBlock(_ selected: [ExportModel], port: Int) -> [String: Any] {
        [
            "id": providerID,
            "name": "KorpProxy",
            "baseURL": "http://127.0.0.1:\(port)/v1",
            "envVar": envVar,
            "models": selected.flatMap { modelEntries($0) },
        ]
    }

    /// Returns (modelCount, backupURL?). `backupURL` is nil when no prior config
    /// existed (a fresh file was created).
    @discardableResult
    static func export(_ models: [ExportModel], port: Int) throws -> (Int, URL?) {
        let url = configURL()
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var root: [String: Any] = [:]
        var backupURL: URL?
        if let data = try? Data(contentsOf: url) {
            guard let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                throw ExportError.unreadable(url.path)
            }
            root = parsed
            let backup = dir.appendingPathComponent("config.json.korpproxy-\(backupStamp()).bak")
            try? data.write(to: backup)
            backupURL = backup
        }

        // Keep existing providers; replace any prior KorpProxy one.
        var providers = (root["providers"] as? [[String: Any]]) ?? []
        providers.removeAll { ($0["id"] as? String) == providerID }
        let selected = models.filter(\.isSelected)
        providers.append(providerBlock(selected, port: port))
        root["providers"] = providers

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
