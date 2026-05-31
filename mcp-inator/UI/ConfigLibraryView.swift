import SwiftUI
import Sentry

struct ConfigLibraryView: View {
    @EnvironmentObject private var store: ConfigStore
    @Binding var selectedConfig: MCPServerConfig?
    let isCompact: Bool
    @State private var showAddConfig = false
    @State private var editingConfig: MCPServerConfig?
    @State private var confirmDelete: MCPServerConfig?
    @State private var statusMatrix: [ConfigStore.StatusRow] = []
    @State private var importSource: ImportSource?
    @State private var importCategories: [(key: String, category: ConfigStore.ImportCategory)] = []

    private var importSources: [ImportSource] { ImportSourceScanner().scan() }

    var body: some View {
        Group {
            if store.configs.isEmpty {
                emptyState
            } else {
                configList
            }
        }
        .onAppear { loadMatrix() }
        .onChange(of: store.configs.count) { _ in loadMatrix() }
        .onChange(of: store.configs.map(\.updatedAt)) { _ in loadMatrix() }
        .navigationTitle("MCP Servers")
        .sheet(isPresented: $showAddConfig) {
            AddEditConfigView()
                .environmentObject(store)
        }
        .navigationDestination(
            isPresented: Binding(
                get: { importSource != nil },
                set: { if !$0 { importSource = nil } }
            )
        ) {
            if let source = importSource {
                ImportReviewView(source: source, categories: importCategories)
                    .environmentObject(store)
            }
        }
        .navigationDestination(
            isPresented: Binding(
                get: { isCompact && editingConfig != nil },
                set: { if !$0 { editingConfig = nil } }
            )
        ) {
            if let config = editingConfig {
                AddEditConfigView(existing: config)
                    .environmentObject(store)
            }
        }
        .confirmationDialog(
            "Delete \"\(confirmDelete?.displayName ?? "")\"?",
            isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let config = confirmDelete {
                    let crumb = Breadcrumb(level: .info, category: "ui")
                    crumb.message = "delete: removing server '\(config.serverKey)' from library"
                    SentrySDK.addBreadcrumb(crumb)
                    try? store.delete(config)
                }
                confirmDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("This removes the server from your library and disables it for all agents.")
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "server.rack")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No MCP Servers")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Add your first MCP server to get started.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Add MCP Server") {
                showAddConfig = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var configList: some View {
        List {
            HStack {
                Button {
                    showAddConfig = true
                } label: {
                    Label("New Server…", systemImage: "plus.circle")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)

                if !importSources.isEmpty {
                    Spacer()
                    Menu {
                        ForEach(importSources, id: \.agentType) { source in
                            Button(source.displayName) { prepareImport(for: source) }
                                .disabled(!source.isImportable)
                                .help(source.unavailableReason ?? "")
                        }
                    } label: {
                        Label("Import…", systemImage: "square.and.arrow.down")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .listRowBackground(Color.clear)

            ForEach(store.configs) { config in
                let row = statusMatrix.first { $0.config.uuid == config.uuid }
                ConfigRow(config: config, agentStates: row?.agentStates ?? [])
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !config.isBuiltIn else { return }
                        if isCompact {
                            editingConfig = config
                        } else {
                            selectedConfig = config
                        }
                    }
                    .listRowBackground(
                        !isCompact && selectedConfig?.uuid == config.uuid
                            ? Color.accentColor.opacity(0.15)
                            : Color.clear
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !config.isBuiltIn {
                            Button(role: .destructive) {
                                confirmDelete = config
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
            }
        }
        .listStyle(.inset)
    }

    private func loadMatrix() {
        statusMatrix = (try? store.fetchStatusMatrix()) ?? []
    }

    private func prepareImport(for source: ImportSource) {
        guard let categories = try? store.categorizeImport(from: source.adapter, configPath: source.configPath) else { return }
        importCategories = categories
        importSource = source
    }
}

// MARK: - ConfigRow

private struct ConfigRow: View {
    let config: MCPServerConfig
    let agentStates: [(agent: AgentRecord, state: EffectiveState)]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(config.displayName)
                    .fontWeight(.medium)
                if config.isBuiltIn {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(config.serverKey)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            HStack(spacing: 4) {
                if config.isHTTP {
                    Image(systemName: "network")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(config.url)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Image(systemName: "terminal")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(config.displayCommand)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    if !config.args.isEmpty {
                        Text(config.args.joined(separator: " "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            if !config.envVars.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "key")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(config.envVars.count) env var\(config.envVars.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            if !agentStates.isEmpty {
                HStack(spacing: 4) {
                    ForEach(agentStates, id: \.agent.agentType) { pair in
                        AgentStateBadge(agent: pair.agent, state: pair.state)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - AgentStateBadge (FR-009: distinct colors for enabled/disabled/unavailable)

private struct AgentStateBadge: View {
    let agent: AgentRecord
    let state: EffectiveState

    private var stateColor: Color {
        switch state {
        case .enabled:     return .green
        case .disabled:    return .secondary
        case .unavailable: return .orange
        }
    }

    private var tooltip: String {
        switch state {
        case .enabled:            return "\(agent.displayName): enabled"
        case .disabled:           return "\(agent.displayName): disabled"
        case .unavailable(let reason): return "\(agent.displayName): unavailable — \(reason)"
        }
    }

    var body: some View {
        AgentIcon(agentType: agent.agentType)
            .frame(width: 18, height: 18)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(stateColor, lineWidth: 1.5)
            )
            .opacity(state == .disabled ? 0.4 : 1.0)
            .overlay(alignment: .bottomTrailing) {
                if state == .enabled {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5, height: 5)
                        .offset(x: 2, y: 2)
                }
            }
            .help(tooltip)
    }
}

#Preview {
    NavigationStack {
        ConfigLibraryView(selectedConfig: .constant(nil), isCompact: true)
            // swiftlint:disable:next force_try
            .environmentObject(try! ConfigStore())
    }
    .frame(width: 400, height: 500)
}
