import SwiftUI

struct DiscoveryView: View {
    @EnvironmentObject private var store: ConfigStore

    let results: [ConfigStore.DiscoveryResult]
    var onDismiss: () -> Void

    @State private var managedAgentTypes: Set<AgentType>

    init(results: [ConfigStore.DiscoveryResult], onDismiss: @escaping () -> Void) {
        self.results = results
        self.onDismiss = onDismiss
        _managedAgentTypes = State(initialValue: Set(
            results.map(\.agent.agentType).filter { !$0.isAppManaged }
        ))
    }

    var body: some View {
        NavigationStack {
            Group {
                if results.isEmpty {
                    noAgentsFound
                } else {
                    agentList
                }
            }
            .navigationTitle("New Agents Found")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip All") { onDismiss() }
                }
            }
        }
        .frame(width: 480, height: 420)
    }

    // MARK: - Subviews

    private var noAgentsFound: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No AI tools found")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Install Claude Code, Claude Desktop, Gemini CLI, Gemini Desktop, or Codex CLI and relaunch mcp-inator.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Done") { onDismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var agentList: some View {
        VStack(spacing: 0) {
            Text(
                "mcp-inator will read and write the config file for each enabled agent " +
                "to keep your MCP servers in sync. Toggle off any agent you prefer to manage manually."
            )
            .font(.callout)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            List(results, id: \.agent.agentType) { result in
                HStack {
                    if result.agent.agentType.isAppManaged {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Toggle("", isOn: toggleBinding(for: result.agent.agentType))
                            .labelsHidden()
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.agent.displayName)
                            .fontWeight(.medium)
                        if result.agent.agentType.isAppManaged {
                            Text("MCP servers managed internally")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text(result.agent.configPath)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer()
                    if result.agent.agentType.isAppManaged {
                        Text("In-app managed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(.vertical, 2)
            }
            .listStyle(.inset)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Done") { applyAndDismiss() }
                    .buttonStyle(.borderedProminent)
                    .padding()
            }
        }
    }

    // MARK: - Helpers

    private func toggleBinding(for agentType: AgentType) -> Binding<Bool> {
        Binding(
            get: { managedAgentTypes.contains(agentType) },
            set: { enabled in
                if enabled {
                    managedAgentTypes.insert(agentType)
                } else {
                    managedAgentTypes.remove(agentType)
                }
            }
        )
    }

    private func applyAndDismiss() {
        for result in results where !result.agent.agentType.isAppManaged {
            guard let agentId = result.agent.id else { continue }
            let managed = managedAgentTypes.contains(result.agent.agentType)
            try? store.setAgentVisibility(agentId: agentId, visible: managed)
            if managed, let adapter = AdapterRegistry.adapter(for: result.agent.agentType) {
                try? store.autoImport(agent: result.agent, adapter: adapter)
            }
        }
        onDismiss()
    }
}
