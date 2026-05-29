import AppKit
import Foundation
import Observation

enum ProxyStatus: Equatable {
    case stopped
    case starting
    case running(port: Int)
    case failed(String)

    var symbolName: String {
        switch self {
        case .stopped: return "bolt.slash"
        case .starting: return "bolt.badge.clock"
        case .running: return "bolt.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    var label: String {
        switch self {
        case .stopped: return "Stopped"
        case .starting: return "Starting…"
        case .running(let port): return "Running on :\(port)"
        case .failed(let message): return "Failed: \(message)"
        }
    }

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

@Observable
final class AppState {
    var status: ProxyStatus = .stopped
    var logTail: [String] = []

    let config = ConfigStore()
    let customModels: CustomModelsStore
    let updater = UpdaterManager()

    @ObservationIgnored
    var proxy: ProxyManager!
    @ObservationIgnored
    let modelsServer: LocalModelsServer

    init() {
        let store = CustomModelsStore(baseDir: config.baseDir)
        customModels = store
        let server = LocalModelsServer(initial: store.models)
        modelsServer = server
        proxy = ProxyManager(state: self)

        // Keep the catalog server's snapshot in sync with edits.
        store.onChange = { models in server.updateModels(models) }

        // Stop the engine cleanly when the app quits — don't leak the child process.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.proxy.stop()
            self?.modelsServer.stop()
        }

        // Start the local catalog server first so KORP_MODELS_URL is set before
        // the engine launches, then auto-start the engine.
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let port = try? await server.start(preferredPort: UInt16(self.config.port + 1)) {
                self.proxy.modelsCatalogURL = "http://127.0.0.1:\(port)/models.json"
                self.appendLog("models catalog server listening on 127.0.0.1:\(port)")
            } else {
                self.appendLog("models catalog server unavailable — using upstream catalog directly")
            }
            self.proxy.start()
        }
    }

    /// Push the latest custom models and restart the engine so they take effect now.
    func applyCustomModels() {
        modelsServer.updateModels(customModels.models)
        proxy.restart()
    }

    func appendLog(_ line: String) {
        logTail.append(line)
        if logTail.count > 500 {
            logTail.removeFirst(logTail.count - 500)
        }
    }
}
