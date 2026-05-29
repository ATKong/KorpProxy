import SwiftUI

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

        Settings {
            SettingsView()
                .environment(app)
        }
    }
}
