import AppKit
import SwiftUI

// MARK: - Overview

/// Landing section: engine status at a glance plus quick facts and actions.
struct OverviewView: View {
    @Environment(AppState.self) private var app
    @Environment(Navigation.self) private var nav

    private var dashboardURL: URL? { URL(string: "http://127.0.0.1:\(app.config.port)/") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                statusCard
                factsCard
                quickActions
            }
            .padding(Theme.Spacing.xl)
        }
    }

    private var statusCard: some View {
        Card(padding: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.md) {
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .fill(EngineStatusStyle.color(app.status).opacity(0.16))
                    .frame(width: 46, height: 46)
                    .overlay(
                        Image(systemName: app.status.symbolName)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(EngineStatusStyle.color(app.status))
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text("Engine").font(Theme.Font.caption).foregroundStyle(Theme.Colors.textTertiary)
                    Text(app.status.label).font(Theme.Font.sectionTitle)
                }
                Spacer()
                if app.status.isRunning {
                    EngineActionButton(title: "Restart", symbol: "arrow.clockwise") { app.proxy.restart() }
                    EngineActionButton(title: "Stop", symbol: "stop.fill", tint: Theme.Colors.failed) { app.proxy.stop() }
                } else {
                    EngineActionButton(title: "Start", symbol: "play.fill", tint: Theme.Colors.running) { app.proxy.start() }
                }
            }
        }
    }

    private var factsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "Connection")
                    .padding(.bottom, Theme.Spacing.sm)
                infoRow("Address", "127.0.0.1:\(app.config.port)")
                Divider().overlay(Theme.Colors.border)
                infoRow("Config", app.config.configPath.path, mono: true)
                Divider().overlay(Theme.Colors.border)
                infoRow("Auth directory", app.config.authDir.path, mono: true)
            }
        }
    }

    private func infoRow(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
            Text(label)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(mono ? Theme.Font.mono : Theme.Font.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Quick actions")
            HStack(spacing: Theme.Spacing.sm) {
                actionTile("Accounts", "person.2") { nav.go(to: .accounts) }
                actionTile("Models", "cube.box") { nav.go(to: .models) }
                actionTile("Usage", "chart.bar") { nav.go(to: .usage) }
                if let url = dashboardURL, app.status.isRunning {
                    actionTile("Dashboard", "safari") { NSWorkspace.shared.open(url) }
                }
            }
        }
    }

    private func actionTile(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.Colors.accent)
                Text(title).font(Theme.Font.captionMedium).foregroundStyle(Theme.Colors.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.Colors.panel, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .strokeBorder(Theme.Colors.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A bordered pill button used for engine actions in cards.
struct EngineActionButton: View {
    let title: String
    let symbol: String
    var tint: Color = Theme.Colors.accent
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(title).font(Theme.Font.captionMedium)
            }
            .padding(.horizontal, Theme.Spacing.md).padding(.vertical, 7)
            .background(tint.opacity(hovering ? 0.24 : 0.15),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            .foregroundStyle(tint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Logs

/// Full-height monospaced tail of the engine's stdout/stderr.
struct LogsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if app.logTail.isEmpty {
                            Text("No output yet.")
                                .font(Theme.Font.mono)
                                .foregroundStyle(Theme.Colors.textTertiary)
                                .padding(.top, Theme.Spacing.sm)
                        } else {
                            ForEach(Array(app.logTail.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(Theme.Font.mono)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }
                    }
                    .padding(Theme.Spacing.lg)
                }
                .onChange(of: app.logTail.count) { _, count in
                    withAnimation { proxy.scrollTo(count - 1, anchor: .bottom) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
    }
}

// MARK: - Usage

/// Per-account usage windows (5h / 7d) with reset countdowns, driven by the
/// same management API the Accounts section uses.
struct UsageView: View {
    @Environment(AppState.self) private var app
    @State private var model = AccountsModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if !app.status.isRunning {
                    placeholder("Start the engine to view usage.", symbol: "bolt.slash")
                } else if model.accounts.isEmpty {
                    placeholder(model.loading ? "Loading usage…" : "No accounts to report usage for.",
                                symbol: "chart.bar")
                } else {
                    ForEach(model.accounts) { account in
                        accountCard(account)
                    }
                }
            }
            .padding(Theme.Spacing.xl)
        }
        .task {
            model.configure(port: app.config.port, secret: app.config.managementSecret)
            guard app.status.isRunning else { return }
            await model.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: AccountsModel.usageRefreshInterval)
                await model.refreshUsage()
            }
        }
    }

    private func accountCard(_ account: Account) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: 10) {
                    ProviderIcon(provider: account.provider, size: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.email ?? account.name).font(Theme.Font.bodyMedium)
                        Text(account.provider ?? "unknown")
                            .font(Theme.Font.caption).foregroundStyle(Theme.Colors.textTertiary)
                    }
                    Spacer()
                    if model.usage(for: account)?.isRateLimited == true { RateLimitedPill() }
                }
                if let u = model.usage(for: account)?.usage, u.hasData {
                    DetailedUsageView(usage: u)
                } else {
                    Text("No usage data reported.")
                        .font(Theme.Font.caption).foregroundStyle(Theme.Colors.textTertiary)
                }
            }
        }
    }

    private func placeholder(_ text: String, symbol: String) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 26))
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(text).font(Theme.Font.body).foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

// MARK: - Settings / General

/// General settings (startup, updates, engine info) restyled for the new shell.
struct GeneralSettingsView: View {
    @Environment(AppState.self) private var app
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                startupCard
                updatesCard
                engineCard
            }
            .padding(Theme.Spacing.xl)
        }
    }

    private var startupCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SectionHeader(title: "Startup")
                Toggle("Launch KorpProxy at login", isOn: $launchAtLogin)
                    .font(Theme.Font.body)
                    .toggleStyle(.switch)
                    .tint(Theme.Colors.accent)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            try LoginItem.setEnabled(newValue)
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = LoginItem.isEnabled
                        }
                    }
                if let loginError {
                    Text(loginError).font(Theme.Font.caption).foregroundStyle(Theme.Colors.failed)
                }
            }
        }
    }

    private var updatesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SectionHeader(title: "Updates")
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { app.updater.automaticallyChecksForUpdates },
                    set: { app.updater.automaticallyChecksForUpdates = $0 }
                ))
                .font(Theme.Font.body)
                .toggleStyle(.switch)
                .tint(Theme.Colors.accent)
                HStack {
                    EngineActionButton(title: "Check Now", symbol: "arrow.down.circle") {
                        app.updater.checkForUpdates()
                    }
                    .disabled(!app.updater.canCheckForUpdates)
                    Spacer()
                    Text("Version \(appVersion)")
                        .font(Theme.Font.caption).foregroundStyle(Theme.Colors.textTertiary)
                }
            }
        }
    }

    private var engineCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "Engine")
                    .padding(.bottom, Theme.Spacing.sm)
                settingRow("Status", app.status.label)
                Divider().overlay(Theme.Colors.border)
                settingRow("Port", "\(app.config.port)")
                Divider().overlay(Theme.Colors.border)
                settingRow("Config", app.config.configPath.path, mono: true)
                Divider().overlay(Theme.Colors.border)
                settingRow("Auth dir", app.config.authDir.path, mono: true)
            }
        }
    }

    private func settingRow(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
            Text(label)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(mono ? Theme.Font.mono : Theme.Font.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, Theme.Spacing.sm)
    }
}
