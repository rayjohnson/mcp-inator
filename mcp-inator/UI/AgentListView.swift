import SwiftUI

// Shows all library configs for a specific agent with enable/disable toggles.
// Handles drift detection, conflict detection, restart notifications, and path overrides.
struct AgentListView: View {
    @EnvironmentObject private var store: ConfigStore
    let agent: AgentRecord

    @State private var enabledUUIDs: Set<UUID> = []
    @State private var pendingWrite: PendingWrite?
    @State private var showRestartNotice = false
    @State private var showPathOverride = false
    @State private var customPathInput: String = ""
    @State private var writeError: String?
    @State private var showImportReview = false
    @State private var importCategories: [(key: String, category: ConfigStore.ImportCategory)] = []
    @State private var multiSelectActive = false
    @State private var multiSelected: Set<UUID> = []

    private struct PendingWrite {
        let uuid: UUID
        let enable: Bool
        let driftResult: WriteResult?
    }

    private var adapter: any AgentAdapter {
        switch agent.agentType {
        case .claudeCode:    return ClaudeCodeAdapter()
        case .claudeDesktop: return ClaudeDesktopAdapter()
        case .geminiCLI:     return GeminiCLIAdapter()
        case .codexCLI:      return CodexCLIAdapter()
        }
    }

    private var configPath: URL { URL(fileURLWithPath: agent.configPath) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            agentHeader
            Divider()
            if let pending = pendingWrite {
                driftView(pending: pending)
            } else if !agent.isAvailable {
                unavailableBanner
            } else if store.configs.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Text("No configs in your library yet.")
                        .foregroundColor(.secondary)
                    Button("Import from \(agent.displayName)…") { triggerImport() }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                configRows
            }
        }
        .navigationTitle(agent.displayName)
        .toolbar { toolbarContent }
        .navigationDestination(isPresented: $showPathOverride) {
            pathOverrideView
        }
        .navigationDestination(isPresented: $showImportReview) {
            ImportReviewView(agent: agent, categories: importCategories)
                .environmentObject(store)
        }
        .alert("Restart Required", isPresented: $showRestartNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            restartMessage
        }
        .alert("Write Failed", isPresented: Binding(
            get: { writeError != nil },
            set: { if !$0 { writeError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(writeError ?? "")
        }
        .onAppear { refreshEnabledSet() }
    }

    // MARK: - Subviews

    private var agentHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.configPath)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if agent.isAvailable {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .help("Agent config file is accessible")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var unavailableBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading) {
                Text("Config file not accessible")
                    .fontWeight(.medium)
                Text(agent.configPath)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("Change Path") {
                customPathInput = agent.configPath
                showPathOverride = true
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
    }

    private var configRows: some View {
        List {
            ForEach(store.configs) { config in
                ConfigAgentRow(
                    config: config,
                    isEnabled: enabledUUIDs.contains(config.uuid),
                    agentAvailable: agent.isAvailable,
                    multiSelectActive: multiSelectActive,
                    isMultiSelected: multiSelected.contains(config.uuid),
                    onToggle: { toggle(config: config) },
                    onMultiSelect: {
                        if multiSelected.contains(config.uuid) {
                            multiSelected.remove(config.uuid)
                        } else {
                            multiSelected.insert(config.uuid)
                        }
                    }
                )
            }
        }
        .listStyle(.inset)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Import from \(agent.displayName)…") { triggerImport() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        if multiSelectActive {
            ToolbarItem(placement: .primaryAction) {
                Button("Apply (\(multiSelected.count))") { applySelected() }
                    .disabled(multiSelected.isEmpty)
                    .buttonStyle(.borderedProminent)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    multiSelectActive = false
                    multiSelected = []
                }
            }
        } else if !store.configs.isEmpty {
            ToolbarItem(placement: .primaryAction) {
                Button("Select") {
                    multiSelectActive = true
                    multiSelected = Set(store.configs.map(\.uuid))
                }
            }
        }
    }

    // MARK: - Toggle Enable/Disable

    private func toggle(config: MCPServerConfig) {
        guard agent.isAvailable, let agentId = agent.id else { return }
        let wasEnabled = enabledUUIDs.contains(config.uuid)
        do {
            try store.refreshAvailability(adapters: [adapter])
            if wasEnabled {
                let result = try store.disableConfig(uuid: config.uuid, agentId: agentId,
                                                     adapter: adapter, configPath: configPath)
                handleResult(result, uuid: config.uuid, enable: false)
            } else {
                let result = try store.enableConfig(uuid: config.uuid, agentId: agentId,
                                                    adapter: adapter, configPath: configPath)
                handleResult(result, uuid: config.uuid, enable: true)
            }
        } catch {
            writeError = describeError(error, configPath: configPath)
        }
    }

    private func handleResult(_ result: WriteResult, uuid: UUID, enable: Bool) {
        switch result {
        case .success:
            refreshEnabledSet()
            showRestartNotice = true
        case .driftDetected:
            pendingWrite = PendingWrite(uuid: uuid, enable: enable, driftResult: result)
        }
    }

    // MARK: - Inline Drift View

    private func driftView(pending: PendingWrite) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(.orange)
            Text("Config file changed externally")
                .font(.title2).fontWeight(.semibold)
            Text("The config file was modified since mcp-inator last wrote it. You can skip this change or override the file with the current config.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            if case .driftDetected(let onDisk, let expected) = pending.driftResult {
                driftDetail(onDisk: onDisk, expected: expected)
            }
            Spacer()
            Divider()
            HStack(spacing: 16) {
                Button("Skip") { pendingWrite = nil }
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button("Override & Write") { forcePendingWrite() }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func driftDetail(onDisk: [String: MCPServerConfig], expected: [String: MCPServerConfig]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(expected.keys.sorted()), id: \.self) { key in
                let exp = expected[key]
                let disk = onDisk[key]
                if exp?.command != disk?.command {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Expected").font(.caption).foregroundColor(.secondary)
                            Text(exp?.command ?? "(none)").font(.caption).monospaced()
                        }
                        Image(systemName: "arrow.right")
                        VStack(alignment: .leading) {
                            Text("On Disk").font(.caption).foregroundColor(.secondary)
                            Text(disk?.command ?? "(none)").font(.caption).monospaced()
                        }
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private func forcePendingWrite() {
        guard let pending = pendingWrite, let agentId = agent.id else { return }
        do {
            if pending.enable {
                _ = try store.enableConfig(uuid: pending.uuid, agentId: agentId,
                                           adapter: adapter, configPath: configPath, force: true)
            } else {
                _ = try store.disableConfig(uuid: pending.uuid, agentId: agentId,
                                            adapter: adapter, configPath: configPath, force: true)
            }
            refreshEnabledSet()
            showRestartNotice = true
        } catch {
            writeError = describeError(error, configPath: configPath)
        }
        pendingWrite = nil
    }

    // MARK: - Restart Notice

    private var restartMessage: Text {
        if agent.agentType == .geminiCLI {
            return Text("Restart Gemini CLI, or run `/mcp reload` in an active session.")
        }
        return Text("Restart \(agent.displayName) to apply the change.")
    }

    // MARK: - Path Override (navigation destination)

    private var pathOverrideView: some View {
        VStack(spacing: 0) {
            Form {
                Section("Config File Path") {
                    TextField("Path", text: $customPathInput)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("Cancel") { showPathOverride = false }
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button("Save") {
                    if let agentId = agent.id {
                        try? store.updateAgentConfigPath(agentId: agentId, path: customPathInput)
                    }
                    showPathOverride = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(customPathInput.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .navigationTitle("Change Config Path")
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Import

    private func triggerImport() {
        do {
            importCategories = try store.categorizeImport(from: adapter, configPath: configPath)
            showImportReview = true
        } catch {
            writeError = describeError(error, configPath: configPath)
        }
    }

    // MARK: - Bulk Apply (T047)

    private func applySelected() {
        guard let agentId = agent.id else { return }
        let uuids = Array(multiSelected)
        do {
            let result = try store.bulkEnableConfigs(uuids: uuids, agentId: agentId,
                                                     adapter: adapter, configPath: configPath)
            refreshEnabledSet()
            if !result.succeeded.isEmpty { showRestartNotice = true }
            if let firstFailed = result.failed.first {
                writeError = describeError(firstFailed.1, configPath: configPath)
            }
        } catch {
            writeError = describeError(error, configPath: configPath)
        }
        multiSelectActive = false
        multiSelected = []
    }

    // MARK: - Helpers

    private func refreshEnabledSet() {
        guard let agentId = agent.id else { return }
        enabledUUIDs = (try? Set(store.fetchEnabledConfigs(for: agentId).map(\.uuid))) ?? []
    }

    // FR-012: specific error messages with file path and cause
    private func describeError(_ error: Error, configPath: URL) -> String {
        if let adapterErr = error as? AdapterError {
            switch adapterErr {
            case .parseFailure(let url, let underlying):
                return "Failed to read \(url.path): \(underlying.localizedDescription)"
            case .writeFailure(let url, let underlying):
                return "Failed to write \(url.path): \(underlying.localizedDescription). Check file permissions."
            }
        }
        return "\(configPath.path): \(error.localizedDescription)"
    }
}

// MARK: - ConfigAgentRow

private struct ConfigAgentRow: View {
    let config: MCPServerConfig
    let isEnabled: Bool
    let agentAvailable: Bool
    let multiSelectActive: Bool
    let isMultiSelected: Bool
    let onToggle: () -> Void
    let onMultiSelect: () -> Void

    var body: some View {
        HStack {
            if multiSelectActive {
                Image(systemName: isMultiSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isMultiSelected ? .accentColor : .secondary)
                    .onTapGesture { onMultiSelect() }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(config.displayName)
                    .fontWeight(.medium)
                Group {
                    if config.isHTTP {
                        Text(config.url)
                    } else {
                        Text(([config.command] + config.args).joined(separator: " "))
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            }
            Spacer()
            if !agentAvailable {
                Text("Unavailable")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15))
                    .foregroundColor(.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else if !multiSelectActive {
                Toggle("", isOn: Binding(get: { isEnabled }, set: { _ in onToggle() }))
                    .labelsHidden()
            }
        }
        .padding(.vertical, 2)
    }
}
