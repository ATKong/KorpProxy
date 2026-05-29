import SwiftUI

struct ModelsView: View {
    @Environment(AppState.self) private var app
    @State private var sheet: ModelSheet?
    @State private var available = AvailableModelsModel()

    private enum ModelSheet: Identifiable {
        case add
        case edit(CustomModel)
        case exportFactory
        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let m): return m.uuid.uuidString
            case .exportFactory: return "export"
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
            case .exportFactory:
                FactoryExportView(models: exportModels(),
                                  port: app.config.port,
                                  apiKey: app.config.apiKey)
            }
        }
    }

    /// Build the export list: custom models (with thinking levels) first, then
    /// available models, de-duplicated by model id.
    private func exportModels() -> [ExportModel] {
        var byID: [String: ExportModel] = [:]
        var order: [String] = []
        for m in app.customModels.models {
            guard byID[m.modelID] == nil else { continue }
            byID[m.modelID] = ExportModel(
                include: true, modelID: m.modelID, displayName: m.displayName,
                isAnthropic: m.provider == "claude",
                maxOutputTokens: m.maxCompletionTokens,
                levels: m.thinkingLevels, sourceLabel: "Custom")
            order.append(m.modelID)
        }
        for group in available.groups {
            for sm in group.models where byID[sm.id] == nil {
                let isAnthropic = (sm.ownedBy?.lowercased().contains("anthropic") ?? false)
                    || sm.id.hasPrefix("claude")
                byID[sm.id] = ExportModel(
                    include: true, modelID: sm.id, displayName: "",
                    isAnthropic: isAnthropic, maxOutputTokens: 0,
                    levels: available.levels(for: sm.id) ?? ["low", "medium", "high"],
                    sourceLabel: group.provider)
                order.append(sm.id)
            }
        }
        return order.compactMap { byID[$0] }
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
            Button { sheet = .exportFactory } label: {
                Label("Export to Factory", systemImage: "square.and.arrow.up")
            }
            .help("Write these models into ~/.factory/settings.json (pointed at KorpProxy)")
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

/// Lets the user pick KorpProxy models and write them into Factory's
/// customModels (pointed at the local KorpProxy server).
private struct FactoryExportView: View {
    @Environment(\.dismiss) private var dismiss
    let port: Int
    let apiKey: String

    @State private var rows: [ExportModel]
    @State private var resultText: String?
    @State private var errorText: String?

    init(models: [ExportModel], port: Int, apiKey: String) {
        self.port = port
        self.apiKey = apiKey
        _rows = State(initialValue: models)
    }

    private var selectedCount: Int { rows.filter(\.include).count }
    private var entryCount: Int { rows.filter(\.include).reduce(0) { $0 + $1.entryCount } }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Export to Factory").font(.headline)
                    Spacer()
                    Button("Done") { dismiss() }
                }
                Text("Each model is exported once per reasoning level. Factory can’t pick reasoning for custom models, so the level is encoded in the model name (e.g. \u{2026}-4-8(high)) and KorpProxy applies it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            Divider()
            content
            Divider()
            HStack {
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(resultText != nil ? Color.green : .secondary)
                Spacer()
                Button("Export \(entryCount) entries") { runExport() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedCount == 0)
            }
            .padding(14)
        }
        .frame(width: 540, height: 580)
    }

    private var statusLine: String {
        if let resultText { return resultText }
        if rows.isEmpty { return "Nothing to export." }
        return "\(selectedCount) of \(rows.count) models · \(entryCount) entries → 127.0.0.1:\(port)"
    }

    @ViewBuilder private var content: some View {
        if let errorText {
            ContentUnavailableView {
                Label("Couldn’t export", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if rows.isEmpty {
            ContentUnavailableView {
                Label("Nothing to export", systemImage: "tray")
            } description: {
                Text("Add a custom model or log in to an account first.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(grouped, id: \.0) { label, indices in
                    Section(label) {
                        ForEach(indices, id: \.self) { i in
                            HStack(spacing: 10) {
                                Toggle("", isOn: $rows[i].include).labelsHidden()
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rows[i].displayName.isEmpty ? rows[i].modelID : rows[i].displayName)
                                    Text(rows[i].modelID)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(rows[i].isAnthropic ? "anthropic" : "openai")
                                    .font(.caption2).foregroundStyle(.tertiary)
                                if rows[i].levels.isEmpty {
                                    Text("NO REASONING")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(.secondary.opacity(0.12), in: Capsule())
                                } else {
                                    ForEach(rows[i].levels, id: \.self) { level in
                                        Text(level.uppercased())
                                            .font(.caption2.weight(.medium))
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(.tint.opacity(0.15), in: Capsule())
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    /// Row indices grouped by source label, preserving order.
    private var grouped: [(String, [Int])] {
        var order: [String] = []
        var map: [String: [Int]] = [:]
        for (i, row) in rows.enumerated() {
            if map[row.sourceLabel] == nil { order.append(row.sourceLabel) }
            map[row.sourceLabel, default: []].append(i)
        }
        return order.map { ($0, map[$0]!) }
    }

    private func runExport() {
        do {
            let (models, entries, backup) = try FactoryExport.export(rows, port: port, apiKey: apiKey)
            resultText = "Exported \(entries) entries from \(models) model(s). Backup: \(backup.lastPathComponent)"
            errorText = nil
        } catch {
            errorText = error.localizedDescription
            resultText = nil
        }
    }
}
