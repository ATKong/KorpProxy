import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            AccountsView()
                .tabItem { Label("Accounts", systemImage: "person.2") }
        }
        .frame(width: 560, height: 520)
    }
}

private struct GeneralSettingsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Form {
            Section("Engine") {
                LabeledContent("Status", value: app.status.label)
                LabeledContent("Port", value: "\(app.config.port)")
                LabeledContent("Config", value: app.config.configPath.path)
                LabeledContent("Auth dir", value: app.config.authDir.path)
            }

            Section("Logs") {
                ScrollView {
                    Text(app.logTail.isEmpty ? "No output yet." : app.logTail.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 200)
            }
        }
        .formStyle(.grouped)
    }
}
