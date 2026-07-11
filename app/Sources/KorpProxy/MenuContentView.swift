import AppKit
import SwiftUI

struct MenuContentView: View {
    @Environment(AppState.self) private var app
    @Environment(\.openWindow) private var openWindow
    @State private var accounts = AccountsModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            controls
            Divider().overlay(Theme.Colors.border)
            accountsSection
            Divider().overlay(Theme.Colors.border)
            footer
        }
        .padding(14)
        .frame(width: 300)
        .task(id: app.status) {
            accounts.configure(port: app.config.port, secret: app.config.managementSecret)
            guard app.status.isRunning else { return }
            await accounts.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: AccountsModel.usageRefreshInterval)
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
                Text("KorpProxy").font(Theme.Font.headerTitle)
                Text(subtitle).font(Theme.Font.caption).foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            StatusPill(text: EngineStatusStyle.pillText(app.status), color: statusColor)
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

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 8) {
            if app.status.isRunning {
                EngineActionButton(title: "Stop", symbol: "stop.fill", tint: Theme.Colors.failed) { app.proxy.stop() }
                EngineActionButton(title: "Restart", symbol: "arrow.clockwise", tint: Theme.Colors.textSecondary) { app.proxy.restart() }
            } else {
                EngineActionButton(title: "Start", symbol: "play.fill", tint: Theme.Colors.running) { app.proxy.start() }
            }
            Spacer()
            if app.status.isRunning, let url = dashboardURL {
                Link(destination: url) {
                    Image(systemName: "safari").foregroundStyle(Theme.Colors.textSecondary)
                }
                .help("Open dashboard")
            }
        }
    }

    private var dashboardURL: URL? { URL(string: "http://127.0.0.1:\(app.config.port)/") }

    // MARK: Accounts

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                SectionHeader(title: "Accounts")
                Spacer()
                if accounts.loading {
                    ProgressView().controlSize(.mini)
                } else if app.status.isRunning {
                    Text("\(accounts.accounts.count)").font(Theme.Font.caption).foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            if !app.status.isRunning {
                Text("Start the engine to manage accounts.")
                    .font(Theme.Font.caption).foregroundStyle(Theme.Colors.textSecondary)
            } else if accounts.accounts.isEmpty {
                Text("No accounts yet — models won’t serve until you add one.")
                    .font(Theme.Font.caption).foregroundStyle(Theme.Colors.textSecondary)
            } else {
                ForEach(accounts.accounts.prefix(4)) { acct in
                    let info = accounts.usage(for: acct)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            ProviderIcon(provider: acct.provider, size: 16)
                            Text(acct.email ?? acct.name).font(Theme.Font.caption).lineLimit(1)
                            Spacer()
                            if info?.isRateLimited == true { RateLimitedPill() }
                            Circle()
                                .fill(acct.disabled == true ? Theme.Colors.starting : Theme.Colors.running)
                                .frame(width: 6, height: 6)
                        }
                        if let u = info?.usage, u.hasData {
                            CompactUsageView(usage: u).padding(.leading, 24)
                        }
                    }
                }
                if accounts.accounts.count > 4 {
                    Text("+\(accounts.accounts.count - 4) more")
                        .font(Theme.Font.caption).foregroundStyle(Theme.Colors.textTertiary)
                }
            }

            MenuRow(icon: "person.2", title: "Manage accounts…") { openMainWindow(section: .accounts) }
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
            MenuRow(icon: "gearshape", title: "Settings…") { openMainWindow(section: .settings) }
            MenuRow(icon: "power", title: "Quit KorpProxy") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    /// Opens the main window at the given section and brings it to the front.
    /// KorpProxy is a menu-bar accessory (LSUIElement), so without explicit
    /// activation the window can open behind whatever app currently has focus.
    private func openMainWindow(section: AppSection) {
        app.nav.selection = section
        openWindow(id: mainWindowID)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows
                .first { $0.identifier?.rawValue == mainWindowID }?
                .makeKeyAndOrderFront(nil)
        }
    }

    private var statusColor: Color { EngineStatusStyle.color(app.status) }
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
            Image(systemName: icon).frame(width: 16).foregroundStyle(Theme.Colors.textSecondary)
            Text(title).font(Theme.Font.body).foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(hovering ? Theme.Colors.hover : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
