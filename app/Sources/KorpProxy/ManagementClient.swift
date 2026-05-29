import Foundation

/// Async client for the engine's Management API (`/v0/management`).
/// Authenticates with the management secret as a bearer token (the engine reads
/// it from the `MANAGEMENT_PASSWORD` env we pass when spawning it).
struct ManagementClient {
    let port: Int
    let secret: String

    enum ClientError: LocalizedError {
        case badStatus(Int, String)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .badStatus(let code, let body):
                return body.isEmpty ? "HTTP \(code)" : "HTTP \(code): \(body)"
            case .badResponse:
                return "Unexpected response from engine"
            }
        }
    }

    private func makeURL(_ path: String, query: [URLQueryItem]) -> URL? {
        var comps = URLComponents()
        comps.scheme = "http"
        comps.host = "127.0.0.1"
        comps.port = port
        comps.path = "/v0/management" + path
        if !query.isEmpty { comps.queryItems = query }
        return comps.url
    }

    @discardableResult
    private func request(_ path: String, method: String = "GET",
                         query: [URLQueryItem] = [], body: Data? = nil) async throws -> Data {
        guard let url = makeURL(path, query: query) else { throw ClientError.badResponse }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw ClientError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw ClientError.badStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    /// True if the proxy answers on its port at all (any HTTP response counts).
    func ping() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/") else { return false }
        return ((try? await URLSession.shared.data(from: url)) != nil)
    }

    // MARK: Accounts

    func listAccounts() async throws -> [Account] {
        let data = try await request("/auth-files")
        return try JSONDecoder().decode(AuthFilesResponse.self, from: data).files
    }

    func deleteAccount(name: String) async throws {
        try await request("/auth-files", method: "DELETE",
                          query: [URLQueryItem(name: "name", value: name)])
    }

    // MARK: OAuth

    func startOAuth(path: String) async throws -> OAuthStart {
        let data = try await request("/" + path, query: [URLQueryItem(name: "is_webui", value: "true")])
        let start = try JSONDecoder().decode(OAuthStart.self, from: data)
        guard !start.url.isEmpty else { throw ClientError.badResponse }
        return start
    }

    func authStatus(state: String) async throws -> OAuthStatus {
        let data = try await request("/get-auth-status", query: [URLQueryItem(name: "state", value: state)])
        return try JSONDecoder().decode(OAuthStatus.self, from: data)
    }

    func submitCallback(provider: String, redirectURL: String, state: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "provider": provider, "redirect_url": redirectURL, "state": state,
        ])
        try await request("/oauth-callback", method: "POST", body: body)
    }

    // MARK: API keys

    /// Append an API key to a provider list without clobbering existing entries.
    /// `segment` is e.g. "gemini-api-key", "claude-api-key", "codex-api-key".
    func addAPIKey(segment: String, apiKey: String, baseURL: String?) async throws {
        let getData = try await request("/" + segment)
        var list: [[String: Any]] = []
        if let obj = try? JSONSerialization.jsonObject(with: getData) as? [String: Any],
           let existing = obj[segment] as? [[String: Any]] {
            list = existing
        }
        var entry: [String: Any] = ["api-key": apiKey]
        if let baseURL, !baseURL.isEmpty { entry["base-url"] = baseURL }
        list.append(entry)
        let putBody = try JSONSerialization.data(withJSONObject: list)
        try await request("/" + segment, method: "PUT", body: putBody)
    }
}

// MARK: - Models

struct AuthFilesResponse: Decodable {
    let files: [Account]
}

/// A logged-in provider account, as returned by `GET /v0/management/auth-files`.
struct Account: Identifiable, Decodable, Hashable {
    var id: String { name }
    let name: String
    let provider: String?
    let email: String?
    let status: String?
    let disabled: Bool?

    private enum CodingKeys: String, CodingKey {
        case name, provider, type, email, status, disabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        let p = try? c.decode(String.self, forKey: .provider)
        let t = try? c.decode(String.self, forKey: .type)
        provider = (p?.isEmpty == false) ? p : t
        email = try? c.decode(String.self, forKey: .email)
        status = try? c.decode(String.self, forKey: .status)
        disabled = try? c.decode(Bool.self, forKey: .disabled)
    }
}

struct OAuthStart: Decodable {
    let url: String
    let state: String
}

struct OAuthStatus: Decodable {
    let status: String   // "wait" | "ok" | "error"
    let error: String?
}
