import AppKit
import Foundation
import Observation

/// A provider the engine can authenticate, either via an OAuth browser flow or
/// by storing an API key.
struct LoginProvider: Identifiable, Hashable {
    enum Kind: Hashable { case oauth, apiKey }
    let id: String       // canonical key (oauth) or list segment (apiKey)
    let display: String
    let symbol: String
    let kind: Kind
    let path: String     // oauth: "<provider>-auth-url"; apiKey: "<provider>-api-key"
}

enum OAuthPhase: Equatable {
    case idle
    case waiting
    case success
    case failed(String)
}

/// Drives the Accounts UI: lists logged-in accounts and runs the add/login flows
/// against the engine's management API.
@MainActor
@Observable
final class AccountsModel {
    var accounts: [Account] = []
    var loading = false
    var errorMessage: String?

    /// Usage/limiter info keyed by account name (from GET /usage).
    var usageByName: [String: UsageAccount] = [:]

    // Active OAuth session
    var activeProvider: LoginProvider?
    var authURL: URL?
    var oauthState: String?
    var phase: OAuthPhase = .idle
    var manualCallback: String = ""

    private var client: ManagementClient?
    private var pollTask: Task<Void, Never>?

    static let oauthProviders: [LoginProvider] = [
        .init(id: "gemini", display: "Gemini CLI", symbol: "sparkle", kind: .oauth, path: "gemini-cli-auth-url"),
        .init(id: "anthropic", display: "Claude (Anthropic)", symbol: "a.circle", kind: .oauth, path: "anthropic-auth-url"),
        .init(id: "codex", display: "Codex (OpenAI)", symbol: "o.circle", kind: .oauth, path: "codex-auth-url"),
        .init(id: "antigravity", display: "Antigravity", symbol: "arrow.up.circle", kind: .oauth, path: "antigravity-auth-url"),
        .init(id: "kimi", display: "Kimi", symbol: "k.circle", kind: .oauth, path: "kimi-auth-url"),
        .init(id: "xai", display: "xAI (Grok)", symbol: "x.circle", kind: .oauth, path: "xai-auth-url"),
    ]

    static let apiKeyProviders: [LoginProvider] = [
        .init(id: "gemini-api-key", display: "Gemini API key", symbol: "key", kind: .apiKey, path: "gemini-api-key"),
        .init(id: "claude-api-key", display: "Claude API key", symbol: "key", kind: .apiKey, path: "claude-api-key"),
        .init(id: "codex-api-key", display: "Codex API key", symbol: "key", kind: .apiKey, path: "codex-api-key"),
    ]

    func configure(port: Int, secret: String) {
        client = ManagementClient(port: port, secret: secret)
    }

    func refresh() async {
        guard let client else { return }
        loading = true
        errorMessage = nil
        do {
            accounts = try await client.listAccounts()
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
        await refreshUsage()
    }

    /// Fetch per-account usage/limiter status (best-effort; never surfaces errors).
    func refreshUsage() async {
        guard let client else { return }
        if let list = try? await client.usageStatus() {
            usageByName = Dictionary(list.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }

    func usage(for account: Account) -> UsageAccount? {
        usageByName[account.name]
    }

    func delete(_ account: Account) async {
        guard let client else { return }
        do {
            try await client.deleteAccount(name: account.name)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: OAuth

    func beginOAuth(_ provider: LoginProvider) {
        guard let client else { return }
        cancelOAuth()
        activeProvider = provider
        phase = .waiting
        authURL = nil
        oauthState = nil
        manualCallback = ""
        pollTask = Task { [weak self] in
            guard let self else { return }
            do {
                let start = try await client.startOAuth(path: provider.path)
                self.oauthState = start.state
                if let url = URL(string: start.url) {
                    self.authURL = url
                    NSWorkspace.shared.open(url)
                }
                await self.pollUntilDone(state: start.state)
            } catch {
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    private func pollUntilDone(state: String) async {
        guard let client else { return }
        let deadline = Date().addingTimeInterval(300)
        while Date() < deadline {
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let status = try? await client.authStatus(state: state) else { continue }
            switch status.status {
            case "ok":
                phase = .success
                await refresh()
                return
            case "error":
                phase = .failed(status.error ?? "Authentication failed")
                return
            default:
                continue
            }
        }
        phase = .failed("Timed out waiting for sign-in")
    }

    func submitManualCallback() {
        guard let client, let provider = activeProvider, let state = oauthState else { return }
        let urlString = manualCallback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty else { return }
        Task { [weak self] in
            try? await client.submitCallback(provider: provider.id, redirectURL: urlString, state: state)
            self?.manualCallback = ""
        }
    }

    func cancelOAuth() {
        pollTask?.cancel()
        pollTask = nil
    }

    func resetOAuth() {
        cancelOAuth()
        activeProvider = nil
        authURL = nil
        oauthState = nil
        phase = .idle
        manualCallback = ""
    }

    // MARK: API key

    func addAPIKey(_ provider: LoginProvider, apiKey: String, baseURL: String) async -> Bool {
        guard let client else { return false }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return false }
        errorMessage = nil
        do {
            try await client.addAPIKey(segment: provider.path, apiKey: key,
                                       baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines))
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

/// SF Symbol for a provider string returned by the engine.
func providerSymbol(_ provider: String?) -> String {
    let p = (provider ?? "").lowercased()
    if p.contains("gemini") { return "sparkle" }
    if p.contains("claude") || p.contains("anthropic") { return "a.circle" }
    if p.contains("codex") || p.contains("openai") { return "o.circle" }
    if p.contains("antigravity") { return "arrow.up.circle" }
    if p.contains("kimi") { return "k.circle" }
    if p.contains("xai") || p.contains("grok") { return "x.circle" }
    return "person.crop.circle"
}
