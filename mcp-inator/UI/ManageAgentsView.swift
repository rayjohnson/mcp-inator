import SwiftUI

struct ManageAgentsView: View {
    @EnvironmentObject private var store: ConfigStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            List(store.agents) { agent in
                HStack {
                    AgentIcon(agentType: agent.agentType)
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(agent.displayName)
                            .fontWeight(.medium)
                        Text(agent.isAvailable ? "Available" : "Not installed")
                            .font(.caption)
                            .foregroundColor(agent.isAvailable ? .secondary : .orange)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { agent.isVisible },
                        set: { newValue in
                            guard let agentId = agent.id else { return }
                            try? store.setAgentVisibility(agentId: agentId, visible: newValue)
                        }
                    ))
                    .labelsHidden()
                }
                .padding(.vertical, 2)
            }
            .listStyle(.inset)

            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .navigationTitle("Manage Agents")
        .navigationBarBackButtonHidden(false)
    }
}
