import Foundation
import Network

/// A tiny loopback HTTP server that serves the engine's model catalog.
///
/// On each request it fetches the live upstream models.json (cached briefly),
/// merges the user's custom models into it, and returns the result. The engine
/// is pointed here via `KORP_MODELS_URL`, so newly-added models appear the next
/// time the engine refreshes (we restart it to make that instant). If upstream
/// can't be reached and we have no cache, it returns 503 so the engine falls
/// through to upstream's own URLs.
final class LocalModelsServer: @unchecked Sendable {
    private let upstreamURLs = [
        URL(string: "https://raw.githubusercontent.com/router-for-me/models/refs/heads/main/models.json")!,
        URL(string: "https://models.router-for.me/models.json")!,
    ]
    private let cacheTTL: TimeInterval = 300

    private let queue = DispatchQueue(label: "io.korp.models-server")
    private var listener: NWListener?

    private let lock = NSLock()
    private var customModels: [CustomModel] = []
    private var cachedBase: Data?
    private var cachedAt: Date?

    private(set) var port: UInt16 = 0

    init(initial: [CustomModel]) {
        customModels = initial
    }

    /// Replace the served custom-model set (thread-safe).
    func updateModels(_ models: [CustomModel]) {
        lock.lock(); customModels = models; lock.unlock()
    }

    private func currentModels() -> [CustomModel] {
        lock.lock(); defer { lock.unlock() }
        return customModels
    }

    /// Bind to the first free loopback port at/after `preferredPort`.
    func start(preferredPort: UInt16) async throws -> UInt16 {
        for candidate in preferredPort..<(preferredPort &+ 25) {
            if (try? await bind(on: candidate)) != nil {
                port = candidate
                return candidate
            }
        }
        throw NSError(domain: "LocalModelsServer", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "no free loopback port near \(preferredPort)"])
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func bind(on candidate: UInt16) async throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1",
                                                  port: NWEndpoint.Port(rawValue: candidate)!)
        let newListener = try NWListener(using: params)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var resumed = false
            newListener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if !resumed { resumed = true; cont.resume() }
                case .failed(let err), .waiting(let err):
                    newListener.cancel()
                    if !resumed { resumed = true; cont.resume(throwing: err) }
                default:
                    break
                }
            }
            newListener.newConnectionHandler = { [weak self] conn in
                self?.handle(conn)
            }
            self.listener = newListener
            newListener.start(queue: queue)
        }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        // Read (and ignore) the request line/headers, then respond.
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] _, _, _, _ in
            guard let self else { conn.cancel(); return }
            Task {
                let body = await self.catalogJSON()
                self.respond(conn, body: body)
            }
        }
    }

    private func respond(_ conn: NWConnection, body: Data?) {
        let status: String
        let contentType: String
        let payload: Data
        if let body {
            status = "200 OK"; contentType = "application/json"; payload = body
        } else {
            status = "503 Service Unavailable"; contentType = "text/plain"
            payload = Data("upstream models unavailable".utf8)
        }
        let header = "HTTP/1.1 \(status)\r\n"
            + "Content-Type: \(contentType)\r\n"
            + "Content-Length: \(payload.count)\r\n"
            + "Connection: close\r\n\r\n"
        var out = Data(header.utf8)
        out.append(payload)
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }

    private func catalogJSON() async -> Data? {
        guard let base = await fetchBase() else { return nil }
        return ModelCatalogMerger.merged(base: base, custom: currentModels())
    }

    private func fetchBase() async -> Data? {
        lock.lock()
        let cached = cachedBase
        let freshEnough = cachedAt.map { Date().timeIntervalSince($0) < cacheTTL } ?? false
        lock.unlock()
        if let cached, freshEnough { return cached }

        for url in upstreamURLs {
            var req = URLRequest(url: url)
            req.timeoutInterval = 20
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse, http.statusCode == 200,
               (try? JSONSerialization.jsonObject(with: data)) != nil {
                lock.lock(); cachedBase = data; cachedAt = Date(); lock.unlock()
                return data
            }
        }
        // Fall back to a stale cache if we have one.
        lock.lock(); let stale = cachedBase; lock.unlock()
        return stale
    }
}
