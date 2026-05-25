import SwiftUI

// Root popover content. Uses a tab view: Servers (config library) and Agents.
struct MenuBarView: View {
    @EnvironmentObject var store: ConfigStore

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
        }
        .frame(width: 420, height: 520)
        .onAppear {
            try? store.refreshAvailability(adapters: allAdapters)
        }
    }

    private var allAdapters: [any AgentAdapter] {
        [ClaudeCodeAdapter(), ClaudeDesktopAdapter(), GeminiCLIAdapter(), CodexCLIAdapter()]
    }
}

// MARK: - AgentsTabView

private struct AgentsTabView: View {
    @EnvironmentObject private var store: ConfigStore

    var body: some View {
        List(store.agents) { agent in
            NavigationLink(destination: AgentListView(agent: agent).environmentObject(store)) {
                AgentRow(agent: agent)
            }
        }
        .listStyle(.inset)
        .navigationTitle("Agents")
        .overlay {
            if store.agents.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "cpu")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No agents discovered yet")
                        .font(.title3)
                        .foregroundColor(.secondary)
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
                Text(agent.configPath)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

#Preview {
    MenuBarView()
        .environmentObject(try! ConfigStore())
}
