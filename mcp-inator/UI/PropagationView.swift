import SwiftUI

// Shown after saving an edit when the config is enabled for one or more agents (T050).
// Displays per-agent diffs (lastWrittenSnapshot vs. updated config) and lets the user
// push changes or skip. Declining is safe — drift detection will catch it on the next write.
struct PropagationView: View {
    @EnvironmentObject private var store: ConfigStore
    @Environment(\.dismiss) private var dismiss

    let config: MCPServerConfig

    @State private var enabledAgents: [AgentRecord] = []
    @State private var snapshots: [Int64: MCPServerConfig] = [:]
    @State private var writeError: String?
    @State private var showRestartNotice = false

    private let adapters: [AgentType: any AgentAdapter] = [
        .claudeCode:    ClaudeCodeAdapter(),
        .claudeDesktop: ClaudeDesktopAdapter(),
        .geminiCLI:     GeminiCLIAdapter(),
        .codexCLI:      CodexCLIAdapter()
    ]

    var body: some View {
        VStack(spacing: 0) {
            if enabledAgents.isEmpty {
                loadingState
            } else {
                agentDiffList
            }
            if let err = writeError {
                Text(err)
                    .foregroundColor(.red)
                    .font(.callout)
                    .padding(.horizontal)
            }
        }
        .navigationTitle("Push Changes")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Skip") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Push to All") { pushAll() }
                    .disabled(enabledAgents.isEmpty)
            }
        }
        .alert("Restart Required", isPresented: $showRestartNotice) {
            Button("OK") { dismiss() }
        } message: {
            Text("Restart each affected agent to apply the changes.")
        }
        .onAppear { loadAgents() }
    }

    // MARK: - Subviews

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Checking enabled agents…")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var agentDiffList: some View {
        List(enabledAgents) { agent in
            VStack(alignment: .leading, spacing: 6) {
                Text(agent.displayName)
                    .fontWeight(.medium)
                if let snap = snapshots[agent.id ?? -1] {
                    diffRow(label: "Was", value: snap.command)
                    diffRow(label: "Now", value: config.command)
                    if snap.args != config.args {
                        diffRow(label: "Args were", value: snap.args.joined(separator: " "))
                        diffRow(label: "Args now", value: config.args.joined(separator: " "))
                    }
                } else {
                    Text("Will be written for the first time")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .listStyle(.inset)
    }

    private func diffRow(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label + ":")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
        }
    }

    // MARK: - Logic

    private func loadAgents() {
        do {
            enabledAgents = try store.findEnabledAgents(for: config.uuid)
            for agent in enabledAgents {
                guard let agentId = agent.id else { continue }
                let assignment = try store.fetchAssignment(configUUID: config.uuid, agentId: agentId)
                if let snap = assignment?.lastWrittenSnapshot {
                    snapshots[agentId] = snap
                }
            }
        } catch {
            writeError = "Failed to load agents: \(error.localizedDescription)"
        }
    }

    private func pushAll() {
        var anyWritten = false
        for agent in enabledAgents {
            guard let agentId = agent.id,
                  let adapter = adapters[agent.agentType] else { continue }
            let path = URL(fileURLWithPath: agent.configPath)
            do {
                let result = try store.enableConfig(uuid: config.uuid, agentId: agentId,
                                                    adapter: adapter, configPath: path)
                if case .success = result { anyWritten = true }
            } catch {
                writeError = "Failed to push to \(agent.displayName): \(error.localizedDescription)"
                return
            }
        }
        if anyWritten { showRestartNotice = true } else { dismiss() }
    }
}
