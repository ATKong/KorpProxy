import SwiftUI

/// Lists logged-in provider accounts and lets the user add or remove them
/// without ever touching the engine's web management panel.
struct AccountsView: View {
    @Environment(AppState.self) private var app
    @State private var model = AccountsModel()
    @State private var showAdd = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .task {
            model.configure(port: app.config.port, secret: app.config.managementSecret)
            await model.refresh()
        }
        .sheet(isPresented: $showAdd) {
            AddAccountSheet(model: model)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Accounts").font(.headline)
            if model.loading { ProgressView().controlSize(.small) }
            Spacer()
            Button { Task { await model.refresh() } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
            Button { showAdd = true } label: { Label("Add Account", systemImage: "plus") }
                .disabled(!app.status.isRunning)
        }
        .padding(12)
    }

    @ViewBuilder private var content: some View {
        if model.accounts.isEmpty {
            if model.loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = model.errorMessage {
                ContentUnavailableView {
                    Label("Couldn’t reach engine", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(err)
                }
            } else {
                ContentUnavailableView {
                    Label("No accounts yet", systemImage: "person.crop.circle.badge.plus")
                } description: {
                    Text("Add a provider account to start serving models.")
                } actions: {
                    Button("Add Account") { showAdd = true }.disabled(!app.status.isRunning)
                }
            }
        } else {
            List {
                ForEach(model.accounts) { account in
                    AccountRow(account: account) { Task { await model.delete(account) } }
                }
            }
            .listStyle(.inset)
        }
    }
}

private struct AccountRow: View {
    let account: Account
    let onDelete: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: providerSymbol(account.provider))
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.email ?? account.name).font(.body)
                HStack(spacing: 6) {
                    Text(account.provider ?? "unknown")
                        .font(.caption).foregroundStyle(.secondary)
                    if let s = account.status, !s.isEmpty {
                        Text(s)
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
            Spacer()
            Button(role: .destructive) { confirmDelete = true } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .confirmationDialog("Remove “\(account.name)”?", isPresented: $confirmDelete) {
                Button("Remove", role: .destructive, action: onDelete)
                Button("Cancel", role: .cancel) {}
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AddAccountSheet: View {
    @Bindable var model: AccountsModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: LoginProvider?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                if selected != nil {
                    Button { model.resetOAuth(); selected = nil } label: {
                        Image(systemName: "chevron.left")
                    }
                }
                Text("Add Account").font(.title3).bold()
                Spacer()
                Button("Done") { model.resetOAuth(); dismiss() }
            }

            if let provider = selected {
                if provider.kind == .oauth {
                    OAuthFlowView(model: model, provider: provider)
                } else {
                    APIKeyFormView(model: model, provider: provider) { dismiss() }
                }
            } else {
                providerPicker
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(width: 460, height: 430)
    }

    private var providerPicker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Sign in with OAuth").font(.headline)
                grid(AccountsModel.oauthProviders)
                Divider()
                Text("Add an API key").font(.headline)
                grid(AccountsModel.apiKeyProviders)
            }
        }
    }

    private func grid(_ providers: [LoginProvider]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 10)], spacing: 10) {
            ForEach(providers) { p in
                Button {
                    selected = p
                    if p.kind == .oauth { model.beginOAuth(p) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: p.symbol)
                        Text(p.display).lineLimit(1)
                        Spacer()
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct OAuthFlowView: View {
    @Bindable var model: AccountsModel
    let provider: LoginProvider

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Signing in to \(provider.display)", systemImage: provider.symbol)
                .font(.headline)

            switch model.phase {
            case .waiting:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for browser sign-in…")
                }
                if let url = model.authURL {
                    Text("If your browser didn’t open, use this link:")
                        .font(.caption).foregroundStyle(.secondary)
                    Link(url.absoluteString, destination: url).font(.caption).lineLimit(2)
                }
                DisclosureGroup("Paste callback URL manually") {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("http://localhost/...?code=...&state=...",
                                  text: $model.manualCallback, axis: .vertical)
                            .textFieldStyle(.roundedBorder).lineLimit(1...3)
                        Button("Submit callback") { model.submitManualCallback() }
                            .disabled(model.manualCallback.isEmpty)
                    }
                    .padding(.top, 4)
                }
                .font(.caption)

            case .success:
                Label("Signed in successfully", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)

            case .failed(let msg):
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Button("Try again") { model.beginOAuth(provider) }

            case .idle:
                ProgressView()
            }
        }
    }
}

private struct APIKeyFormView: View {
    @Bindable var model: AccountsModel
    let provider: LoginProvider
    let onDone: () -> Void
    @State private var apiKey = ""
    @State private var baseURL = ""
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Add \(provider.display)", systemImage: provider.symbol).font(.headline)
            TextField("API key", text: $apiKey).textFieldStyle(.roundedBorder)
            TextField("Base URL (optional)", text: $baseURL).textFieldStyle(.roundedBorder)
            if let err = model.errorMessage {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button(saving ? "Saving…" : "Save") {
                    saving = true
                    Task {
                        let ok = await model.addAPIKey(provider, apiKey: apiKey, baseURL: baseURL)
                        saving = false
                        if ok { onDone() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(apiKey.isEmpty || saving)
            }
        }
    }
}
