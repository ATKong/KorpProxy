import Foundation

/// Supervises the KorpProxy engine (the Go `cli-proxy-api` server) as a child
/// process: locates the binary, launches it with our managed config, tails its
/// output, health-checks the port, and stops it cleanly.
final class ProxyManager {
    private weak var state: AppState?
    private let config: ConfigStore
    private var process: Process?

    init(state: AppState) {
        self.state = state
        self.config = state.config
    }

    /// Resolve the engine binary: env override → app bundle → dev build dir.
    func binaryURL() -> URL? {
        let env = ProcessInfo.processInfo.environment
        if let override = env["KORP_PROXY_BIN"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        if let bundled = Bundle.main.url(forResource: "korpproxy-server", withExtension: nil) {
            return bundled
        }
        // Dev fallback: <repo>/app/.engine-bin/korpproxy-server (see scripts/build-engine.sh).
        let dev = URL(fileURLWithPath: #filePath) // …/app/Sources/KorpProxy/ProxyManager.swift
            .deletingLastPathComponent()           // …/app/Sources/KorpProxy
            .deletingLastPathComponent()           // …/app/Sources
            .deletingLastPathComponent()           // …/app
            .appendingPathComponent(".engine-bin/korpproxy-server")
        return FileManager.default.isExecutableFile(atPath: dev.path) ? dev : nil
    }

    func start() {
        guard process == nil else { return }
        guard let binary = binaryURL() else {
            setStatus(.failed("engine binary not found — run app/scripts/build-engine.sh"))
            return
        }
        setStatus(.starting)

        let proc = Process()
        proc.executableURL = binary
        proc.arguments = ["--config", config.configPath.path]
        var env = ProcessInfo.processInfo.environment
        // Expose the management secret as MANAGEMENT_PASSWORD so the app can call
        // the engine's /v0/management API with a plaintext bearer token. (The
        // config secret-key is bcrypt-compared, which a plaintext value fails.)
        if !config.managementSecret.isEmpty {
            env["MANAGEMENT_PASSWORD"] = config.managementSecret
        }
        proc.environment = env
        // Launch with a writable cwd so any engine relative paths resolve here
        // (a GUI app launched via `open` otherwise inherits cwd = "/").
        proc.currentDirectoryURL = config.baseDir

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            for line in text.split(whereSeparator: \.isNewline) where !line.isEmpty {
                let entry = String(line)
                DispatchQueue.main.async { self?.state?.appendLog(entry) }
            }
        }
        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.process = nil
                self?.setStatus(.stopped)
            }
        }

        do {
            try proc.run()
            process = proc
            waitForHealth()
        } catch {
            process = nil
            setStatus(.failed(error.localizedDescription))
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        setStatus(.stopped)
    }

    func restart() {
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.start()
        }
    }

    /// Poll the server port until it answers (or we give up after ~10s).
    private func waitForHealth() {
        let port = config.port
        guard let url = URL(string: "http://127.0.0.1:\(port)/") else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            for _ in 0..<40 {
                let semaphore = DispatchSemaphore(value: 0)
                var reachable = false
                let task = URLSession.shared.dataTask(with: url) { _, response, _ in
                    if response != nil { reachable = true }
                    semaphore.signal()
                }
                task.resume()
                _ = semaphore.wait(timeout: .now() + 1)
                if reachable {
                    self?.setStatus(.running(port: port))
                    return
                }
                Thread.sleep(forTimeInterval: 0.25)
            }
        }
    }

    private func setStatus(_ status: ProxyStatus) {
        DispatchQueue.main.async { [weak self] in
            self?.state?.status = status
        }
    }
}
