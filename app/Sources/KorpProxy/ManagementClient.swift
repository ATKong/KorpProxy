import Foundation

/// Thin async client for the engine's Management API (`/v0/management`).
/// MVP exposes a port-level health ping; richer endpoints (accounts, models,
/// request logs) will be layered on as the app grows.
struct ManagementClient {
    let port: Int
    let secret: String

    var managementBase: URL? {
        URL(string: "http://127.0.0.1:\(port)/v0/management")
    }

    /// True if the proxy answers on its port at all (any HTTP response counts).
    func ping() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/") else { return false }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return response is HTTPURLResponse
        } catch {
            return false
        }
    }
}
