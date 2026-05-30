import SwiftUI

enum SidebarSection: String, Hashable {
    case servers, agents, catalog
}

struct MainWindowView: View {
    @EnvironmentObject private var store: ConfigStore
    @EnvironmentObject private var storeContainer: StoreContainer
    @EnvironmentObject private var registryStore: RegistryStore
    @EnvironmentObject private var catalogStore: CatalogStore
    @State private var selectedSection: SidebarSection = .servers
    @State private var showAddServer = false

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
            } detail: {
                switch selectedSection {
                case .servers:
                    NavigationStack {
                        ConfigLibraryView()
                            .environmentObject(store)
                    }
                case .agents:
                    NavigationStack {
                        AgentsView()
                            .environmentObject(store)
                    }
                case .catalog:
                    NavigationStack {
                        CatalogView()
                            .environmentObject(registryStore)
                            .environmentObject(store)
                    }
                }
            }
            .frame(minWidth: 800, minHeight: 500)
            .toolbar {
                if selectedSection == .servers {
                    ToolbarItem(placement: .primaryAction) {
                        Button(
                            action: { showAddServer = true },
                            label: { Label("Add Server", systemImage: "plus") }
                        )
                    }
                }
            }
            .sheet(isPresented: $showAddServer) {
                AddEditConfigView()
                    .environmentObject(store)
            }
        } else {
            StoreUnavailableView()
        }
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
        .frame(minWidth: 800, minHeight: 500)
    }
}
