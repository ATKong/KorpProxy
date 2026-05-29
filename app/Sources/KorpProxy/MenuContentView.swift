import AppKit
import SwiftUI

struct MenuContentView: View {
    @Environment(AppState.self) private var app
    @Environment(\.openSettings) private var openSettings
    @State private var accounts = AccountsModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            controls
            Divider()
            accountsSection
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 300)
        .task(id: app.status) {
            accounts.configure(port: app.config.port, secret: app.config.managementSecret)
            guard app.status.isRunning else { return }
            await accounts.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await accounts.refreshUsage()
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(statusColor.opacity(0.16))
                .frame(width: 38, height: 38)
                .overlay(
                    Image(systemName: app.status.symbolName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(statusColor)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text("KorpProxy").font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            statusPill
        }
    }

    private var subtitle: String {
        switch app.status {
        case .running(let port): return "Serving on 127.0.0.1:\(port)"
        case .starting: return "Starting engine…"
        case .stopped: return "Engine stopped"
        case .failed: return "Engine error"
        }
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            Circle().fill(statusColor).frame(width: 7, height: 7)
            Text(pillText).font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(statusColor.opacity(0.12), in: Capsule())
        .foregroundStyle(statusColor)
    }

    private var pillText: String {
        switch app.status {
        case .running: return "On"
        case .starting: return "Starting"
        case .failed: return "Error"
        case .stopped: return "Off"
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 8) {
            if app.status.isRunning {
                Button { app.proxy.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                Button { app.proxy.restart() } label: { Label("Restart", systemImage: "arrow.clockwise") }
            } else {
                Button { app.proxy.start() } label: { Label("Start", systemImage: "play.fill") }
            }
            Spacer()
            if app.status.isRunning, let url = dashboardURL {
                Link(destination: url) { Image(systemName: "safari") }
                    .help("Open dashboard")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var dashboardURL: URL? { URL(string: "http://127.0.0.1:\(app.config.port)/") }

    // MARK: Accounts

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("ACCOUNTS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if accounts.loading {
                    ProgressView().controlSize(.mini)
                } else if app.status.isRunning {
                    Text("\(accounts.accounts.count)").font(.caption2).foregroundStyle(.secondary)
                }
            }

            if !app.status.isRunning {
                Text("Start the engine to manage accounts.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if accounts.accounts.isEmpty {
                Text("No accounts yet — models won’t serve until you add one.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(accounts.accounts.prefix(4)) { acct in
                    let info = accounts.usage(for: acct)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Image(systemName: providerSymbol(acct.provider))
                                .foregroundStyle(.tint).frame(width: 16)
                            Text(acct.email ?? acct.name).font(.caption).lineLimit(1)
                            Spacer()
                            if info?.isRateLimited == true { RateLimitedPill() }
                            Circle()
                                .fill(acct.disabled == true ? Color.orange : Color.green)
                                .frame(width: 6, height: 6)
                        }
                        if let u = info?.usage, u.hasData {
                            CompactUsageView(usage: u).padding(.leading, 24)
                        }
                    }
                }
                if accounts.accounts.count > 4 {
                    Text("+\(accounts.accounts.count - 4) more")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            MenuRow(icon: "person.2", title: "Manage accounts…") { openSettingsWindow() }
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            MenuRow(icon: "folder", title: "Open config folder") {
                NSWorkspace.shared.open(app.config.baseDir)
            }
            MenuRow(icon: "arrow.down.circle", title: "Check for Updates…") {
                app.updater.checkForUpdates()
            }
            .disabled(!app.updater.canCheckForUpdates)
            MenuRow(icon: "gearshape", title: "Settings…") { openSettingsWindow() }
            MenuRow(icon: "power", title: "Quit KorpProxy") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    /// Opens Settings and brings it to the front. KorpProxy is a menu-bar
    /// accessory (LSUIElement), so without explicit activation the Settings
    /// window can open behind whatever app currently has focus.
    private func openSettingsWindow() {
        openSettings()
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows
                .first { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" }?
                .makeKeyAndOrderFront(nil)
        }
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

/// A menu-style row button with hover highlight.
private struct MenuRow: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { MenuRowLabel(icon: icon, title: title) }
            .buttonStyle(.plain)
    }
}

private struct MenuRowLabel: View {
    let icon: String
    let title: String
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon).frame(width: 16).foregroundStyle(.secondary)
            Text(title)
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(hovering ? Color.primary.opacity(0.08) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
