import SwiftUI

struct ModelsView: View {
    @Environment(AppState.self) private var app
    @State private var sheet: ModelSheet?

    private enum ModelSheet: Identifiable {
        case add
        case edit(CustomModel)
        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let m): return m.uuid.uuidString
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add cloud models before upstream lists them. KorpProxy serves these on top of the live catalog, then restarts the engine so they're available immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let url = app.proxy.modelsCatalogURL {
                    Text("Catalog source: \(url)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                } else {
                    Text("Local catalog server unavailable — custom models won’t be served.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .padding(12)

            Divider()

            if app.customModels.models.isEmpty {
                emptyState
            } else {
                List {
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
                .listStyle(.inset)
            }

            Divider()
            HStack {
                Button {
                    sheet = .add
                } label: {
                    Label("Add Model", systemImage: "plus")
                }
                Spacer()
                Button {
                    app.applyCustomModels()
                } label: {
                    Label("Restart engine", systemImage: "arrow.clockwise")
                }
                .help("Re-apply the catalog and restart the engine now")
            }
            .padding(12)
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .add:
                ModelEditor(existing: nil) { saved in app.customModels.add(saved); app.applyCustomModels() }
            case .edit(let model):
                ModelEditor(existing: model) { saved in app.customModels.add(saved); app.applyCustomModels() }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "cube.box").font(.system(size: 34)).foregroundStyle(.secondary)
            Text("No custom models").font(.headline)
            Text("Add a model to serve it before upstream’s catalog includes it.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func delete(_ model: CustomModel) {
        app.customModels.remove(model)
        app.applyCustomModels()
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
        .frame(width: 460, height: 460)
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
        onSave(model)
        dismiss()
    }
}
