import AppKit
import SwiftUI

/// Sections in the main window's sidebar. Order drives the ⌘1…⌘6 shortcuts.
enum AppSection: Int, CaseIterable, Identifiable {
    case overview, accounts, models, usage, logs, settings

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .accounts: return "Accounts"
        case .models: return "Models"
        case .usage: return "Usage"
        case .logs: return "Logs"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .accounts: return "person.2"
        case .models: return "cube.box"
        case .usage: return "chart.bar"
        case .logs: return "text.alignleft"
        case .settings: return "gearshape"
        }
    }

    /// 1-based shortcut number.
    var shortcutNumber: Int { rawValue + 1 }
}

/// Shared navigation + overlay state for the main window.
@Observable
final class Navigation {
    var selection: AppSection = .overview
    var commandPaletteVisible = false

    func go(to section: AppSection) {
        selection = section
        commandPaletteVisible = false
    }
}

/// The Linear-style main window shell: a custom sidebar on the left and a
/// section-driven content area on the right, with a ⌘K command palette overlay.
struct MainWindowView: View {
    @Environment(AppState.self) private var app
    private var nav: Navigation { app.nav }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 208)
            Divider().overlay(Theme.Colors.border)
            ContentContainer()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 860, minHeight: 560)
        .background(Theme.Colors.background)
        .environment(nav)
        .foregroundStyle(Theme.Colors.textPrimary)
        .overlay(shortcutButtons)
        .overlay {
            if nav.commandPaletteVisible {
                CommandPaletteView()
                    .environment(nav)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: nav.commandPaletteVisible)
    }

    /// Invisible buttons that host the window-level keyboard shortcuts.
    private var shortcutButtons: some View {
        ZStack {
            ForEach(AppSection.allCases) { section in
                Button("") { nav.go(to: section) }
                    .keyboardShortcut(KeyEquivalent(Character("\(section.shortcutNumber)")), modifiers: .command)
            }
            Button("") { nav.commandPaletteVisible.toggle() }
                .keyboardShortcut("k", modifiers: .command)
            Button("") {
                if app.status.isRunning { app.proxy.restart() }
            }
            .keyboardShortcut("r", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .frame(width: 0, height: 0)
    }
}

// MARK: - Sidebar

private struct SidebarView: View {
    @Environment(AppState.self) private var app
    @Environment(Navigation.self) private var nav

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            identity
            Divider().overlay(Theme.Colors.border).padding(.horizontal, Theme.Spacing.md)

            VStack(spacing: 2) {
                ForEach(AppSection.allCases) { section in
                    navItem(section)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.top, Theme.Spacing.sm)

            Spacer(minLength: 0)
            engineControl
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.Colors.sidebar)
    }

    private var identity: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .fill(EngineStatusStyle.color(app.status).opacity(0.16))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: app.status.symbolName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(EngineStatusStyle.color(app.status))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("KorpProxy").font(Theme.Font.headerTitle)
                StatusPill(text: EngineStatusStyle.pillText(app.status),
                           color: EngineStatusStyle.color(app.status))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.md)
    }

    private func navItem(_ section: AppSection) -> some View {
        HoverRow(selected: nav.selection == section, action: { nav.go(to: section) }) {
            HStack(spacing: 10) {
                Image(systemName: section.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(nav.selection == section ? Theme.Colors.accent : Theme.Colors.textSecondary)
                Text(section.title)
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(nav.selection == section ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                Spacer(minLength: 0)
                ShortcutHint(["⌘", "\(section.shortcutNumber)"])
                    .opacity(nav.selection == section ? 1 : 0.55)
            }
        }
    }

    private var engineControl: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Divider().overlay(Theme.Colors.border)
            HStack(spacing: Theme.Spacing.sm) {
                if app.status.isRunning {
                    EngineButton(title: "Stop", symbol: "stop.fill", tint: Theme.Colors.failed) { app.proxy.stop() }
                    EngineButton(title: "Restart", symbol: "arrow.clockwise", tint: Theme.Colors.textSecondary) { app.proxy.restart() }
                } else {
                    EngineButton(title: "Start", symbol: "play.fill", tint: Theme.Colors.running) { app.proxy.start() }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.md)
        }
    }
}

/// A small filled engine-control button used in the sidebar footer.
private struct EngineButton: View {
    let title: String
    let symbol: String
    let tint: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(title).font(Theme.Font.captionMedium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(tint.opacity(hovering ? 0.22 : 0.14),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            .foregroundStyle(tint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Content area

private struct ContentContainer: View {
    @Environment(AppState.self) private var app
    @Environment(Navigation.self) private var nav

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.Colors.border)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Theme.Colors.background)
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(nav.selection.title).font(Theme.Font.sectionTitle)
            Spacer()
            Button { nav.commandPaletteVisible = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium))
                    Text("Search").font(Theme.Font.caption)
                    ShortcutHint(["⌘", "K"])
                }
                .padding(.horizontal, Theme.Spacing.sm).padding(.vertical, 5)
                .foregroundStyle(Theme.Colors.textSecondary)
                .background(Theme.Colors.panel, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        .strokeBorder(Theme.Colors.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(height: 48)
    }

    @ViewBuilder private var content: some View {
        switch nav.selection {
        case .overview: OverviewView()
        case .accounts: AccountsView()
        case .models: ModelsView()
        case .usage: UsageView()
        case .logs: LogsView()
        case .settings: GeneralSettingsView()
        }
    }
}

// MARK: - Engine status styling

/// Maps engine status to the design system palette and labels.
enum EngineStatusStyle {
    static func color(_ status: ProxyStatus) -> Color {
        switch status {
        case .running: return Theme.Colors.running
        case .starting: return Theme.Colors.starting
        case .failed: return Theme.Colors.failed
        case .stopped: return Theme.Colors.stopped
        }
    }

    static func pillText(_ status: ProxyStatus) -> String {
        switch status {
        case .running: return "Running"
        case .starting: return "Starting"
        case .failed: return "Error"
        case .stopped: return "Stopped"
        }
    }
}
