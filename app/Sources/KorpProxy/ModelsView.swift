import SwiftUI

struct ModelsView: View {
    @Environment(AppState.self) private var app
    @State private var sheet: ModelSheet?
    @State private var available = AvailableModelsModel()

    private enum ModelSheet: Identifiable {
        case add
        case edit(CustomModel)
        case importFactory
        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let m): return m.uuid.uuidString
            case .importFactory: return "import"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            explainer
            Divider()
            List {
                availableSection
                customSection
            }
            .listStyle(.inset)
            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            available.configure(port: app.config.port, apiKey: app.config.apiKey)
            await available.refresh()
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .add:
                ModelEditor(existing: nil) { saved in app.customModels.add(saved); applyAndRefresh() }
            case .edit(let model):
                ModelEditor(existing: model) { saved in app.customModels.add(saved); applyAndRefresh() }
            case .importFactory:
                FactoryImportView { imported in
                    app.customModels.importModels(imported)
                    applyAndRefresh()
                }
            }
        }
    }

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Models you can call through KorpProxy. The Available list reflects your logged-in accounts; add Custom models to serve ones upstream hasn’t listed yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if app.proxy.modelsCatalogURL == nil {
                Text("Local catalog server unavailable — custom models won’t be served.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
    }

    @ViewBuilder private var availableSection: some View {
        Section {
            if available.loading && available.groups.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading…").font(.caption).foregroundStyle(.secondary)
                }
            } else if available.groups.isEmpty {
                Text(available.errorMessage ?? "No models served yet — add a provider account in the Accounts tab.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(available.groups) { group in
                    DisclosureGroup {
                        ForEach(group.models) { model in
                            Text(model.id)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    } label: {
                        HStack {
                            Text(group.provider).font(.subheadline.weight(.medium))
                            Spacer()
                            Text("\(group.models.count)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text("Available models\(available.total > 0 ? " (\(available.total))" : "")")
                Spacer()
                Button { Task { await available.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh from the engine")
            }
        }
    }

    @ViewBuilder private var customSection: some View {
        Section("Custom models") {
            if app.customModels.models.isEmpty {
                Text("None yet. Add a model to serve it before upstream’s catalog includes it.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(app.customModels.models) { model in
                    ModelRow(model: model)
                        .contentShape(Rectangle())
                        .onTapGesture { sheet = .edit(model) }
                        .swipeActions {
                            Button(role: .destructive) { delete(model) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button { sheet = .add } label: { Label("Add Model", systemImage: "plus") }
            Button { sheet = .importFactory } label: {
                Label("Import from Factory", systemImage: "square.and.arrow.down")
            }
            .help("Import custom models from ~/.factory/settings.json")
            Spacer()
            Button { applyAndRefresh() } label: { Label("Restart engine", systemImage: "arrow.clockwise") }
                .help("Re-apply the catalog and restart the engine now")
        }
        .padding(12)
    }

    private func applyAndRefresh() {
        app.applyCustomModels()
        // Engine restart takes a few seconds; refresh the live list afterwards.
        Task { try? await Task.sleep(for: .seconds(4)); await available.refresh() }
    }

    private func delete(_ model: CustomModel) {
        app.customModels.remove(model)
        applyAndRefresh()
    }
}

private struct ModelRow: View {
    let model: CustomModel

    var body: some View {
        HStack(spacing: 10) {
            Text(ModelProvider.label(model.provider))
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(.tint.opacity(0.15), in: Capsule())
            VStack(alignment: .leading, spacing: 1) {
                Text(model.modelID).font(.system(.body, design: .monospaced))
                if !model.displayName.isEmpty {
                    Text(model.displayName).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.contextLength > 0 {
                Text("\(model.contextLength.formatted()) ctx")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Add/edit form for a custom model.
private struct ModelEditor: View {
    @Environment(\.dismiss) private var dismiss
    let existing: CustomModel?
    let onSave: (CustomModel) -> Void

    @State private var provider: String
    @State private var modelID: String
    @State private var displayName: String
    @State private var type: String
    @State private var ownedBy: String
    @State private var contextLength: String
    @State private var maxCompletionTokens: String
    @State private var modelDescription: String
    @State private var thinkingLevels: Set<String>

    init(existing: CustomModel?, onSave: @escaping (CustomModel) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _provider = State(initialValue: existing?.provider ?? "claude")
        _modelID = State(initialValue: existing?.modelID ?? "")
        _displayName = State(initialValue: existing?.displayName ?? "")
        _type = State(initialValue: existing?.type ?? ModelProvider.find("claude")?.defaultType ?? "")
        _ownedBy = State(initialValue: existing?.ownedBy ?? "")
        _contextLength = State(initialValue: (existing?.contextLength).flatMap { $0 > 0 ? String($0) : nil } ?? "")
        _maxCompletionTokens = State(initialValue: (existing?.maxCompletionTokens).flatMap { $0 > 0 ? String($0) : nil } ?? "")
        _modelDescription = State(initialValue: existing?.modelDescription ?? "")
        _thinkingLevels = State(initialValue: Set(existing?.thinkingLevels ?? []))
    }

    private var isValid: Bool {
        !modelID.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(existing == nil ? "Add Model" : "Edit Model").font(.headline).padding(.top, 14)
            Form {
                Picker("Provider", selection: $provider) {
                    ForEach(ModelProvider.all) { p in Text(p.label).tag(p.key) }
                }
                .onChange(of: provider) { _, newValue in
                    if type.isEmpty || ModelProvider.all.contains(where: { $0.defaultType == type }) {
                        type = ModelProvider.find(newValue)?.defaultType ?? type
                    }
                }

                TextField("Model ID", text: $modelID, prompt: Text("e.g. claude-opus-4-9"))
                TextField("Display name", text: $displayName)
                TextField("Routing type", text: $type, prompt: Text("claude / gemini / openai"))
                TextField("Owned by", text: $ownedBy)
                TextField("Context length", text: $contextLength, prompt: Text("e.g. 200000"))
                TextField("Max completion tokens", text: $maxCompletionTokens)
                TextField("Description", text: $modelDescription, axis: .vertical)

                Section("Thinking / reasoning levels") {
                    HStack(spacing: 6) {
                        ForEach(CustomModel.reasoningLadder, id: \.self) { level in
                            let on = thinkingLevels.contains(level)
                            Button(level) {
                                if on { thinkingLevels.remove(level) } else { thinkingLevels.insert(level) }
                            }
                            .buttonStyle(.bordered)
                            .tint(on ? .accentColor : .gray)
                            .controlSize(.small)
                        }
                    }
                    Text("Levels this model accepts. Leave all off for a non-thinking model.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button(existing == nil ? "Add" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
            .padding(12)
        }
        .frame(width: 460, height: 560)
    }

    private func save() {
        var model = existing ?? CustomModel(modelID: modelID, provider: provider)
        model.modelID = modelID.trimmingCharacters(in: .whitespaces)
        model.provider = provider
        model.displayName = displayName.trimmingCharacters(in: .whitespaces)
        model.type = type.trimmingCharacters(in: .whitespaces)
        model.ownedBy = ownedBy.trimmingCharacters(in: .whitespaces)
        model.contextLength = Int(contextLength.filter(\.isNumber)) ?? 0
        model.maxCompletionTokens = Int(maxCompletionTokens.filter(\.isNumber)) ?? 0
        model.modelDescription = modelDescription
        model.thinkingLevels = CustomModel.reasoningLadder.filter { thinkingLevels.contains($0) }
        onSave(model)
        dismiss()
    }
}

/// Lists models found in ~/.factory/settings.json and imports the selected ones.
private struct FactoryImportView: View {
    @Environment(\.dismiss) private var dismiss
    let onImport: ([CustomModel]) -> Void

    @State private var rows: [Row] = []
    @State private var errorText: String?
    @State private var loaded = false

    struct Row: Identifiable {
        let id = UUID()
        var include = true
        let model: CustomModel
    }

    private var selectedCount: Int { rows.filter(\.include).count }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Import from Factory").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding(14)
            Divider()
            content
            Divider()
            HStack {
                Text(rows.isEmpty ? "" : "\(selectedCount) of \(rows.count) selected")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Import \(selectedCount)") {
                    onImport(rows.filter(\.include).map(\.model))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedCount == 0)
            }
            .padding(14)
        }
        .frame(width: 520, height: 560)
        .task { load() }
    }

    @ViewBuilder private var content: some View {
        if let errorText {
            ContentUnavailableView {
                Label("Couldn’t import", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !loaded {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section {
                    ForEach($rows) { $row in
                        HStack(spacing: 10) {
                            Toggle("", isOn: $row.include).labelsHidden()
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.model.displayName.isEmpty ? row.model.modelID : row.model.displayName)
                                HStack(spacing: 6) {
                                    Text(row.model.modelID)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Text("→ \(ModelProvider.label(row.model.provider))")
                                        .font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            if let top = row.model.thinkingLevels.last {
                                Text(top.uppercased())
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.tint.opacity(0.15), in: Capsule())
                            }
                        }
                    }
                } header: {
                    Text("Found \(rows.count) custom model(s) in ~/.factory/settings.json. Provider is a best guess — edit any after import.")
                        .textCase(nil)
                }
            }
            .listStyle(.inset)
        }
    }

    private func load() {
        do {
            let factory = try FactoryImport.loadFactoryModels()
            rows = factory.map { Row(model: FactoryImport.toCustomModel($0)) }
            loaded = true
        } catch {
            errorText = error.localizedDescription
            loaded = true
        }
    }
}
