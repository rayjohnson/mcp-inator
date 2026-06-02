import SwiftUI

enum SidebarSection: String, Hashable {
    case servers, agents, catalog
}

struct MainWindowView: View {
    @EnvironmentObject private var storeContainer: StoreContainer
    @EnvironmentObject private var registryStore: RegistryStore
    @EnvironmentObject private var catalogStore: CatalogStore
    @State private var selectedSection: SidebarSection = .servers
    @State private var showAddServer = false
    @State private var showManageAgents = false
    @State private var selectedServer: MCPServerConfig?
    @State private var selectedAgent: AgentRecord?
    @State private var selectedCatalogEntry: CatalogViewModel?

    var body: some View {
        if let store = storeContainer.store {
            NavigationSplitView {
                List(selection: $selectedSection) {
                    Label("Servers", systemImage: "server.rack")
                        .tag(SidebarSection.servers)
                    Label("Agents", systemImage: "cpu")
                        .tag(SidebarSection.agents)
                    Label("Catalog", systemImage: "square.grid.2x2")
                        .tag(SidebarSection.catalog)
                }
                .navigationTitle("mcp-inator")
                .listStyle(.sidebar)
            } content: {
                switch selectedSection {
                case .servers:
                    NavigationStack {
                        ConfigLibraryView(selectedConfig: $selectedServer, isCompact: false)
                            .environmentObject(store)
                    }
                case .agents:
                    NavigationStack {
                        AgentsView(
                            showManageAgents: $showManageAgents,
                            selectedAgent: $selectedAgent,
                            isCompact: false
                        )
                        .environmentObject(store)
                    }
                case .catalog:
                    NavigationStack {
                        CatalogView(selectedEntry: $selectedCatalogEntry, isCompact: false)
                            .environmentObject(registryStore)
                            .environmentObject(store)
                    }
                }
            } detail: {
                switch selectedSection {
                case .servers:
                    if let config = selectedServer, !config.isBuiltIn {
                        NavigationStack {
                            AddEditConfigView(existing: config, onDelete: { selectedServer = nil })
                                .environmentObject(store)
                        }
                        .id(config.uuid)
                    } else {
                        DetailPlaceholderView(
                            systemImage: "server.rack",
                            message: "Select a server to edit"
                        )
                    }
                case .agents:
                    if let agent = selectedAgent {
                        NavigationStack {
                            AgentListView(agent: agent)
                                .environmentObject(store)
                        }
                        .id(agent.id)
                    } else {
                        DetailPlaceholderView(
                            systemImage: "cpu",
                            message: "Select an agent to configure"
                        )
                    }
                case .catalog:
                    if let entry = selectedCatalogEntry {
                        NavigationStack {
                            CatalogEntryDetailView(vm: entry)
                                .environmentObject(store)
                        }
                        .id(entry.id)
                    } else {
                        DetailPlaceholderView(
                            systemImage: "square.grid.2x2",
                            message: "Select a server from the catalog"
                        )
                    }
                }
            }
            .frame(minWidth: 900, minHeight: 500)
            .toolbar {
                if selectedSection == .servers {
                    ToolbarItem(placement: .primaryAction) {
                        Button(
                            action: { showAddServer = true },
                            label: { Label("Add Server", systemImage: "plus") }
                        )
                    }
                }
                if selectedSection == .agents {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Manage") { showManageAgents = true }
                    }
                }
            }
            .sheet(isPresented: $showAddServer) {
                AddEditConfigView()
                    .environmentObject(store)
            }
            .onChange(of: store.configs.count) { _ in
                if let current = selectedServer,
                   !store.configs.contains(where: { $0.uuid == current.uuid }) {
                    selectedServer = nil
                }
            }
        } else {
            StoreUnavailableView()
        }
    }
}

private struct DetailPlaceholderView: View {
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(message)
                .font(.title3)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct StoreUnavailableView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("Config library unavailable")
                .font(.title3)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 900, minHeight: 500)
    }
}
