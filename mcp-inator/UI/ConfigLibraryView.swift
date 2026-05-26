import SwiftUI

struct ConfigLibraryView: View {
    @EnvironmentObject private var store: ConfigStore
    @State private var showAddConfig = false
    @State private var editingConfig: MCPServerConfig?
    @State private var confirmDelete: MCPServerConfig?
    @State private var statusMatrix: [ConfigStore.StatusRow] = []

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
        .navigationTitle("MCP Servers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddConfig = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add MCP server")
            }
        }
        .navigationDestination(isPresented: $showAddConfig) {
            AddEditConfigView()
                .environmentObject(store)
        }
        .navigationDestination(
            isPresented: Binding(
                get: { editingConfig != nil },
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
            ForEach(store.configs) { config in
                let row = statusMatrix.first { $0.config.uuid == config.uuid }
                ConfigRow(config: config, agentStates: row?.agentStates ?? [])
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !config.isBuiltIn { editingConfig = config }
                    }
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
                    Text(config.command)
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
        case .unavailable(let r): return "\(agent.displayName): unavailable — \(r)"
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
        ConfigLibraryView()
            .environmentObject(try! ConfigStore())
    }
    .frame(width: 400, height: 500)
}
