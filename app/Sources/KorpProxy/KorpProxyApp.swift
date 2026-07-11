import AppKit
import SwiftUI

/// Stable identifier for the main window, used by openWindow(id:) so the
/// menu-bar accessory can summon it.
let mainWindowID = "korpproxy-main"

@main
struct KorpProxyApp: App {
    @State private var app = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environment(app)
        } label: {
            Image(systemName: app.status.symbolName)
        }
        .menuBarExtraStyle(.window)

        Window("KorpProxy", id: mainWindowID) {
            MainWindowView()
                .environment(app)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 960, height: 620)

        Settings {
            SettingsRedirectView()
                .environment(app)
        }
    }
}

/// The Settings scene is kept only so `openSettings()` has somewhere to land in
/// menus; it immediately routes users to the new main window and closes itself.
private struct SettingsRedirectView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onAppear {
                openWindow(id: mainWindowID)
                dismiss()
            }
    }
}
