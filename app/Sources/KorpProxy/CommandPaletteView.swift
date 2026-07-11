import AppKit
import SwiftUI

/// A single executable command surfaced in the ⌘K palette.
struct PaletteCommand: Identifiable {
    let id = UUID()
    let title: String
    let symbol: String
    let shortcut: [String]?
    let isEnabled: Bool
    let run: () -> Void

    init(title: String, symbol: String, shortcut: [String]? = nil, isEnabled: Bool = true, run: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.shortcut = shortcut
        self.isEnabled = isEnabled
        self.run = run
    }
}

/// Linear-style command palette: a dimmed backdrop with a centered panel near
/// the top of the window, a search field, and a keyboard-navigable results list.
struct CommandPaletteView: View {
    @Environment(AppState.self) private var app
    @Environment(Navigation.self) private var nav

    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            // Dimmed backdrop — click to dismiss.
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { nav.commandPaletteVisible = false }

            panel
                .padding(.top, 88)

            keyHandlers
        }
    }

    /// Invisible buttons hosting palette navigation keys (Esc / arrows).
    private var keyHandlers: some View {
        ZStack {
            Button("") { nav.commandPaletteVisible = false }
                .keyboardShortcut(.cancelAction)
            Button("") { moveHighlight(1) }
                .keyboardShortcut(.downArrow, modifiers: [])
            Button("") { moveHighlight(-1) }
                .keyboardShortcut(.upArrow, modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }

    private func moveHighlight(_ delta: Int) {
        let count = filtered.count
        guard count > 0 else { return }
        highlighted = (highlighted + delta + count) % count
    }

    private var panel: some View {
        VStack(spacing: 0) {
            searchField
            Divider().overlay(Theme.Colors.border)
            results
        }
        .frame(width: 560)
        .background(Theme.Colors.panelRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .strokeBorder(Theme.Colors.borderStrong, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 30, y: 14)
        .onAppear { searchFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Colors.textTertiary)
            TextField("Type a command…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(Theme.Colors.textPrimary)
                .focused($searchFocused)
                .onSubmit(runHighlighted)
                .onChange(of: query) { _, _ in highlighted = 0 }
            ShortcutHint(["esc"])
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(height: 52)
    }

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    let cmds = filtered
                    if cmds.isEmpty {
                        Text("No matching commands")
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.md)
                    } else {
                        ForEach(Array(cmds.enumerated()), id: \.element.id) { index, cmd in
                            row(cmd, index: index)
                                .id(index)
                        }
                    }
                }
                .padding(Theme.Spacing.sm)
            }
            .frame(maxHeight: 360)
            .onChange(of: highlighted) { _, index in
                withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(index, anchor: .center) }
            }
        }
    }

    private func row(_ cmd: PaletteCommand, index: Int) -> some View {
        let isHighlighted = index == highlighted
        return Button {
            execute(cmd)
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: cmd.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 20)
                    .foregroundStyle(isHighlighted ? Theme.Colors.accent : Theme.Colors.textSecondary)
                Text(cmd.title)
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(cmd.isEnabled ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                Spacer(minLength: 0)
                if let shortcut = cmd.shortcut {
                    ShortcutHint(shortcut)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 9)
            .background(isHighlighted ? Theme.Colors.selected : .clear,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!cmd.isEnabled)
        .onHover { if $0 { highlighted = index } }
    }

    // MARK: Behavior

    private func runHighlighted() {
        let cmds = filtered
        guard cmds.indices.contains(highlighted) else { return }
        execute(cmds[highlighted])
    }

    private func execute(_ cmd: PaletteCommand) {
        guard cmd.isEnabled else { return }
        nav.commandPaletteVisible = false
        cmd.run()
    }

    /// Case-insensitive subsequence (fuzzy) match, falling back to substring.
    private var filtered: [PaletteCommand] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return commands }
        return commands.filter { fuzzyMatches(q, $0.title.lowercased()) }
    }

    private func fuzzyMatches(_ needle: String, _ haystack: String) -> Bool {
        if haystack.contains(needle) { return true }
        var idx = needle.startIndex
        for ch in haystack where idx < needle.endIndex && ch == needle[idx] {
            idx = needle.index(after: idx)
        }
        return idx == needle.endIndex
    }

    // MARK: Command catalog

    private var commands: [PaletteCommand] {
        var list: [PaletteCommand] = AppSection.allCases.map { section in
            PaletteCommand(title: "Go to \(section.title)",
                           symbol: section.symbol,
                           shortcut: ["⌘", "\(section.shortcutNumber)"]) {
                nav.go(to: section)
            }
        }

        if app.status.isRunning {
            list.append(PaletteCommand(title: "Stop engine", symbol: "stop.fill") { app.proxy.stop() })
            list.append(PaletteCommand(title: "Restart engine", symbol: "arrow.clockwise", shortcut: ["⌘", "R"]) { app.proxy.restart() })
        } else {
            list.append(PaletteCommand(title: "Start engine", symbol: "play.fill") { app.proxy.start() })
        }

        if app.status.isRunning, let url = URL(string: "http://127.0.0.1:\(app.config.port)/") {
            list.append(PaletteCommand(title: "Open dashboard", symbol: "safari") { NSWorkspace.shared.open(url) })
        }
        list.append(PaletteCommand(title: "Open config folder", symbol: "folder") {
            NSWorkspace.shared.open(app.config.baseDir)
        })
        list.append(PaletteCommand(title: "Check for updates", symbol: "arrow.down.circle",
                                   isEnabled: app.updater.canCheckForUpdates) {
            app.updater.checkForUpdates()
        })
        list.append(PaletteCommand(title: "Quit KorpProxy", symbol: "power") {
            NSApplication.shared.terminate(nil)
        })
        return list
    }
}
