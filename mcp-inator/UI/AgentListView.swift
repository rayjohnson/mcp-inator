import SwiftUI

// Shows all library configs for a specific agent with enable/disable toggles.
// Handles drift detection, conflict detection, restart notifications, and path overrides.
// swiftlint:disable:next type_body_length
struct AgentListView: View {
    @EnvironmentObject private var store: ConfigStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.navigationIsCompact) private var navigationIsCompact
    let agent: AgentRecord

    @State private var enabledUUIDs: Set<UUID> = []
    @State private var pendingWrite: PendingWrite?
    @State private var pendingToggleStates: [UUID: Bool] = [:]
    @State private var restartNotice: String?
    @State private var writeErrorBanner: String?
    @State private var showPathOverride = false
    @State private var customPathInput: String = ""
    @State private var showImportReview = false
    @State private var importCategories: [(key: String, category: ConfigStore.ImportCategory)] = []
    @State private var cloudMCPs: [ClaudeCodeAdapter.CloudManagedMCP] = []

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
        case .geminiDesktop: return GeminiDesktopAdapter()
        }
    }

    private var configPath: URL { URL(fileURLWithPath: agent.configPath) }

    var body: some View {
        // Access enabledUUIDs unconditionally so SwiftUI registers it as a body dependency.
        // Without this, it's only accessed inside List/ForEach (lazy), which doesn't reliably
        // trigger re-renders when the state is set from onAppear.
        _ = enabledUUIDs
        return VStack(alignment: .leading, spacing: 0) {
            agentHeader
            Divider()
            if let pending = pendingWrite {
                driftView(pending: pending)
            } else if adapter.isAppManaged {
                appManagedBanner
            } else if !agent.isAvailable {
                unavailableBanner
            } else if store.configs.isEmpty && cloudMCPs.isEmpty {
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

            if let notice = restartNotice {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(notice)
                        .font(.callout)
                    Spacer()
                    Button("Dismiss") { restartNotice = nil }
                        .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.08))
            }

            if let err = writeErrorBanner {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(err)
                        .font(.callout)
                        .foregroundColor(.red)
                    Spacer()
                    Button("Dismiss") { writeErrorBanner = nil }
                        .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.08))
            }

            if !pendingToggleStates.isEmpty {
                Divider()
                HStack {
                    Button("Cancel") { pendingToggleStates = [:] }
                        .keyboardShortcut(.escape, modifiers: [])
                    Spacer()
                    let count = pendingToggleStates.count
                    Text("\(count) unsaved change\(count == 1 ? "" : "s")")
                        .foregroundColor(.secondary)
                        .font(.callout)
                    Button("Apply") { applyPendingToggles() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .navigationTitle(agent.displayName)
        .toolbar { toolbarContent }
        .navigationDestination(isPresented: $showPathOverride) {
            pathOverrideView
        }
        .navigationDestination(isPresented: $showImportReview) {
            ImportReviewView(
                source: ImportSource(
                    displayName: agent.displayName,
                    agentType: agent.agentType,
                    adapter: adapter,
                    configPath: configPath,
                    isImportable: true,
                    unavailableReason: nil
                ),
                categories: importCategories,
                agentId: agent.id
            )
            .environmentObject(store)
        }
        .onAppear {
            refreshEnabledSet()
            if agent.agentType == .claudeCode {
                cloudMCPs = ClaudeCodeAdapter().cloudMCPs()
            }
        }
        .onChange(of: store.configs.count) { _ in refreshEnabledSet() }
        .onChange(of: store.agents.first(where: { $0.id == agent.id })?.isAvailable) { _ in refreshEnabledSet() }
    }

    // MARK: - Subviews

    private var agentHeader: some View {
        HStack {
            if agent.agentType.isAppManaged {
                Text("MCP configuration is managed inside \(agent.displayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text(agent.configPath)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if agent.isAvailable {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .help("Agent config file is accessible")
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var appManagedBanner: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary)
                Text("Managed In-App")
                    .font(.title3).fontWeight(.semibold)
                Text("\(agent.displayName) stores MCP server configuration internally. Use \(agent.displayName) settings to manage MCP servers.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity)
            Spacer()
        }
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
            ForEach(store.configs, id: \.uuid) { config in
                let displayedEnabled = pendingToggleStates[config.uuid] ?? enabledUUIDs.contains(config.uuid)
                let isPending = pendingToggleStates[config.uuid] != nil
                ConfigAgentRow(
                    config: config,
                    isEnabled: displayedEnabled,
                    isPending: isPending,
                    agentAvailable: agent.isAvailable,
                    onToggle: { togglePending(config: config) }
                )
            }

            if !cloudMCPs.isEmpty {
                Section("Managed via claude.ai") {
                    ForEach(cloudMCPs) { mcp in
                        CloudMCPRow(mcp: mcp)
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if navigationIsCompact {
            ToolbarItem(placement: .navigation) {
                Button(
                    action: { dismiss() },
                    label: { Label("Back", systemImage: "chevron.left") }
                )
            }
        }
        if !agent.agentType.isAppManaged {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Import from \(agent.displayName)…") { triggerImport() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    // MARK: - Pending Toggle Logic

    private func togglePending(config: MCPServerConfig) {
        let actual = enabledUUIDs.contains(config.uuid)
        let current = pendingToggleStates[config.uuid] ?? actual
        let desired = !current
        if desired == actual {
            pendingToggleStates.removeValue(forKey: config.uuid)
        } else {
            pendingToggleStates[config.uuid] = desired
        }
    }

    private func applyPendingToggles() {
        guard let agentId = agent.id else { return }
        do {
            try store.refreshAvailability(adapters: [adapter])
        } catch {
            writeErrorBanner = describeError(error, configPath: configPath)
            return
        }

        var anySuccess = false
        for (uuid, enable) in pendingToggleStates {
            do {
                let result: WriteResult
                if enable {
                    result = try store.enableConfig(uuid: uuid, agentId: agentId,
                                                    adapter: adapter, configPath: configPath)
                } else {
                    result = try store.disableConfig(uuid: uuid, agentId: agentId,
                                                     adapter: adapter, configPath: configPath)
                }
                switch result {
                case .success:
                    anySuccess = true
                case .driftDetected:
                    pendingToggleStates = [:]
                    pendingWrite = PendingWrite(uuid: uuid, enable: enable, driftResult: result)
                    return
                }
            } catch {
                writeErrorBanner = describeError(error, configPath: configPath)
            }
        }
        pendingToggleStates = [:]
        refreshEnabledSet()
        if anySuccess {
            restartNotice = restartMessageText
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
            restartNotice = restartMessageText
        } catch {
            writeErrorBanner = describeError(error, configPath: configPath)
        }
        pendingWrite = nil
    }

    // MARK: - Restart Notice

    private var restartMessageText: String {
        if agent.agentType == .geminiCLI {
            return "Restart Gemini CLI, or run `/mcp reload` in an active session."
        }
        return "Restart \(agent.displayName) to apply the change."
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
            writeErrorBanner = describeError(error, configPath: configPath)
        }
    }

    // MARK: - Helpers

    private func refreshEnabledSet() {
        guard let agentId = agent.id else {
            enabledUUIDs = []
            return
        }
        let liveAvailable = store.agents.first(where: { $0.id == agentId })?.isAvailable ?? agent.isAvailable
        guard liveAvailable else {
            enabledUUIDs = []
            return
        }
        do {
            // Source of truth: the actual file on disk, matched to library configs by serverKey.
            let onDisk = try adapter.readConfigs(from: configPath)
            let diskKeys = Set(onDisk.keys)
            enabledUUIDs = Set(store.configs.compactMap { config in
                diskKeys.contains(config.serverKey) ? config.uuid : nil
            })
            // Sync DB assignment states so that enable/disable operations reconstruct
            // the config map correctly (preserving existing entries not being modified).
            for config in store.configs {
                let state: AssignmentState = diskKeys.contains(config.serverKey) ? .enabled : .disabled
                try? store.setAssignmentState(configUUID: config.uuid, agentId: agentId, state: state)
            }
        } catch {
            // File unreadable — fall back to database assignment state.
            enabledUUIDs = (try? Set(store.fetchEnabledConfigs(for: agentId).map(\.uuid))) ?? []
        }
    }

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
    let isPending: Bool
    let agentAvailable: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(config.displayName)
                        .fontWeight(.medium)
                    if isPending {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                    }
                }
                HStack(spacing: 3) {
                    Image(systemName: config.isHTTP ? "network" : "terminal")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if config.isHTTP {
                        Text(config.url)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(config.transportType.rawValue.uppercased())
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    } else {
                        Text(([config.displayCommand] + config.args).joined(separator: " "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
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
            } else {
                Toggle("", isOn: Binding(get: { isEnabled }, set: { _ in onToggle() }))
                    .labelsHidden()
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - CloudMCPRow

private struct CloudMCPRow: View {
    let mcp: ClaudeCodeAdapter.CloudManagedMCP

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(mcp.displayName)
                    .fontWeight(.medium)
                Text("Managed via claude.ai")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "cloud.fill")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}
