import AppKit
import SwiftUI

/// Linear.app-inspired design system: dark-first tokens implemented with
/// adaptive colors so light mode keeps working. Everything visual (colors,
/// typography, spacing, radii) and the reusable component set lives here.
enum Theme {

    // MARK: Colors

    enum Colors {
        /// App window / deepest background (Linear near-black in dark).
        static let background = adaptive(light: 0xF6F6F7, dark: 0x0E0E11)
        /// Sidebar background — a hair different from the content area.
        static let sidebar = adaptive(light: 0xF1F1F3, dark: 0x111114)
        /// Panel / card surface.
        static let panel = adaptive(light: 0xFFFFFF, dark: 0x151519)
        /// Slightly raised surface (hover / nested).
        static let panelRaised = adaptive(light: 0xFFFFFF, dark: 0x1B1B20)

        /// Hairline borders (Linear uses ~6-8% white in dark).
        static let border = adaptiveAlpha(light: (0x000000, 0.10), dark: (0xFFFFFF, 0.07))
        static let borderStrong = adaptiveAlpha(light: (0x000000, 0.16), dark: (0xFFFFFF, 0.12))

        /// Hover / selection fills.
        static let hover = adaptiveAlpha(light: (0x000000, 0.05), dark: (0xFFFFFF, 0.05))
        static let selected = adaptiveAlpha(light: (0x000000, 0.08), dark: (0xFFFFFF, 0.09))

        /// Text hierarchy.
        static let textPrimary = adaptive(light: 0x18181B, dark: 0xF2F2F4)
        static let textSecondary = adaptive(light: 0x5A5A63, dark: 0x9B9BA6)
        static let textTertiary = adaptive(light: 0x8A8A93, dark: 0x6C6C77)

        /// Single accent — Linear indigo/violet #5E6AD2.
        static let accent = Color(red: 0x5E / 255, green: 0x6A / 255, blue: 0xD2 / 255)
        static let accentSoft = accent.opacity(0.16)

        // Status palette.
        static let running = Color(red: 0.24, green: 0.78, blue: 0.51)
        static let starting = Color(red: 0.95, green: 0.71, blue: 0.24)
        static let failed = Color(red: 0.94, green: 0.38, blue: 0.38)
        static let stopped = adaptive(light: 0x9A9AA3, dark: 0x6C6C77)
    }

    // MARK: Typography

    enum Font {
        static let sectionTitle = SwiftUI.Font.system(size: 15, weight: .semibold)
        static let headerTitle = SwiftUI.Font.system(size: 13, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 13, weight: .regular)
        static let bodyMedium = SwiftUI.Font.system(size: 13, weight: .medium)
        static let caption = SwiftUI.Font.system(size: 11, weight: .regular)
        static let captionMedium = SwiftUI.Font.system(size: 11, weight: .medium)
        static let label = SwiftUI.Font.system(size: 10, weight: .semibold)
        static let mono = SwiftUI.Font.system(size: 11.5, weight: .regular, design: .monospaced)
        static let shortcut = SwiftUI.Font.system(size: 11, weight: .medium, design: .rounded)
    }

    // MARK: Spacing & radii

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 8
        static let large: CGFloat = 10
    }

    // MARK: Adaptive color helpers

    /// Build an adaptive `Color` from light/dark 24-bit RGB hex values.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }

    /// Adaptive color with per-appearance alpha (for borders / overlays).
    static func adaptiveAlpha(light: (UInt32, CGFloat), dark: (UInt32, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let (hex, alpha) = appearance.isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: alpha)
        })
    }
}

private extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

// MARK: - Reusable components

/// Uppercase muted section header used above grouped content.
struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(Theme.Font.label)
            .tracking(0.6)
            .foregroundStyle(Theme.Colors.textTertiary)
    }
}

/// A bordered card/panel container with consistent padding and radius.
struct Card<Content: View>: View {
    var padding: CGFloat = Theme.Spacing.md
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.panel, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .strokeBorder(Theme.Colors.border, lineWidth: 1)
            )
    }
}

/// Small filled status dot.
struct StatusDot: View {
    let color: Color
    var size: CGFloat = 7
    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

/// A capsule status pill with a leading dot.
struct StatusPill: View {
    let text: String
    let color: Color
    var body: some View {
        HStack(spacing: 5) {
            StatusDot(color: color, size: 6)
            Text(text).font(Theme.Font.captionMedium)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(color.opacity(0.14), in: Capsule())
        .foregroundStyle(color)
    }
}

/// A keyboard-shortcut hint label (e.g. ⌘K), rendered as muted key caps.
struct ShortcutHint: View {
    let keys: [String]
    init(_ keys: [String]) { self.keys = keys }
    init(_ combined: String) { self.keys = combined.map(String.init) }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(Theme.Font.shortcut)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .frame(minWidth: 16)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Theme.Colors.hover, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Theme.Colors.border, lineWidth: 1)
                    )
            }
        }
    }
}

/// A hoverable row with rounded highlight — the base for nav/menu/command rows.
struct HoverRow<Content: View>: View {
    var selected: Bool = false
    var action: () -> Void
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(background, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var background: Color {
        if selected { return Theme.Colors.selected }
        return hovering ? Theme.Colors.hover : .clear
    }
}
