import AppKit
import SwiftUI

struct MenuContentView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(statusColor).frame(width: 9, height: 9)
                Text("KorpProxy").font(.headline)
                Spacer()
                Text(app.status.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 8) {
                if app.status.isRunning {
                    Button("Stop") { app.proxy.stop() }
                    Button("Restart") { app.proxy.restart() }
                } else {
                    Button("Start") { app.proxy.start() }
                }
                Spacer()
            }

            if app.status.isRunning, let url = URL(string: "http://127.0.0.1:\(app.config.port)/") {
                Link("Open dashboard", destination: url).font(.caption)
            }

            Divider()

            Button("Open config folder") {
                NSWorkspace.shared.open(app.config.baseDir)
            }
            SettingsLink { Text("Accounts & Settings…") }

            Divider()

            Button("Quit KorpProxy") { NSApplication.shared.terminate(nil) }
        }
        .buttonStyle(.bordered)
        .padding(12)
        .frame(width: 260)
    }

    private var statusColor: Color {
        switch app.status {
        case .running: return .green
        case .starting: return .yellow
        case .failed: return .red
        case .stopped: return .gray
        }
    }
}
