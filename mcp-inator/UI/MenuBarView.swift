import SwiftUI

// Root popover content. Uses a tab view: Servers (config library), Agents, and Catalog.
struct MenuBarView: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var catalogStore: CatalogStore

    var body: some View {
        TabView {
            NavigationStack {
                ConfigLibraryView()
            }
            .tabItem {
                Label("Servers", systemImage: "server.rack")
            }

            NavigationStack {
                AgentsTabView()
            }
            .tabItem {
                Label("Agents", systemImage: "cpu")
            }

            NavigationStack {
                CatalogView()
            }
            .environmentObject(catalogStore)
            .environmentObject(store)
            .tabItem {
                Label("Catalog", systemImage: "square.grid.2x2")
            }
        }
        .frame(width: 420, height: 580)
        .onAppear {
            try? store.refreshAvailability(adapters: allAdapters)
        }
    }

    private var allAdapters: [any AgentAdapter] {
        [ClaudeCodeAdapter(), ClaudeDesktopAdapter(), GeminiCLIAdapter(), CodexCLIAdapter(), GeminiDesktopAdapter()]
    }
}

// MARK: - AgentsTabView

private struct AgentsTabView: View {
    @EnvironmentObject private var store: ConfigStore
    @State private var showManageAgents = false

    var body: some View {
        List(store.visibleAgents) { agent in
            NavigationLink(destination: AgentListView(agent: agent).environmentObject(store)) {
                AgentRow(agent: agent)
            }
        }
        .listStyle(.inset)
        .navigationTitle("Agents")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Manage") { showManageAgents = true }
            }
        }
        .navigationDestination(isPresented: $showManageAgents) {
            ManageAgentsView()
                .environmentObject(store)
        }
        .overlay {
            if store.visibleAgents.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "cpu")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No agents discovered yet")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    if !store.agents.isEmpty {
                        Text("Some agents are hidden — tap Manage to show them.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

private struct AgentRow: View {
    let agent: AgentRecord

    var body: some View {
        HStack {
            Image(systemName: agent.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(agent.isAvailable ? .green : .red)
            VStack(alignment: .leading) {
                Text(agent.displayName)
                    .fontWeight(.medium)
                if agent.agentType.isAppManaged {
                    Text("Managed in-app")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(agent.configPath)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }
}

#Preview {
    MenuBarView()
        .environmentObject(try! ConfigStore())
}
