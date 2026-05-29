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

    @ObservationIgnored
    var proxy: ProxyManager!

    init() {
        proxy = ProxyManager(state: self)

        // Stop the engine cleanly when the app quits — don't leak the child process.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.proxy.stop()
        }

        // Auto-start the engine shortly after launch.
        DispatchQueue.main.async { [weak self] in
            self?.proxy.start()
        }
    }

    func appendLog(_ line: String) {
        logTail.append(line)
        if logTail.count > 500 {
            logTail.removeFirst(logTail.count - 500)
        }
    }
}
