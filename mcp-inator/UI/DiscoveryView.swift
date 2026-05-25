import SwiftUI

struct DiscoveryView: View {
    @EnvironmentObject private var store: ConfigStore
    @Environment(\.dismiss) private var dismiss

    let results: [ConfigStore.DiscoveryResult]

    @State private var importTarget: AgentRecord?
    @State private var showImportReview = false
    @State private var importCategories: [(key: String, category: ConfigStore.ImportCategory)] = []

    private let adapters: [AgentType: any AgentAdapter] = [
        .claudeCode:    ClaudeCodeAdapter(),
        .claudeDesktop: ClaudeDesktopAdapter(),
        .geminiCLI:     GeminiCLIAdapter(),
        .codexCLI:      CodexCLIAdapter()
    ]

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
                    Button("Skip All") { dismiss() }
                }
            }
            .sheet(isPresented: $showImportReview) {
                if let agent = importTarget {
                    ImportReviewView(agent: agent, categories: importCategories)
                        .environmentObject(store)
                }
            }
        }
        .frame(width: 440, height: 380)
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
            Text("Install Claude Code, Claude Desktop, Gemini CLI, or Codex CLI and relaunch mcp-inator.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var agentList: some View {
        List(results, id: \.agent.agentType) { result in
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                VStack(alignment: .leading) {
                    Text(result.agent.displayName)
                        .fontWeight(.medium)
                    Text(result.agent.configPath)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("Import…") {
                    prepareImport(for: result.agent)
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 2)
        }
        .listStyle(.inset)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .padding()
            }
        }
    }

    // MARK: - Import Preparation

    private func prepareImport(for agent: AgentRecord) {
        guard let adapter = adapters[agent.agentType] else { return }
        let configURL = URL(fileURLWithPath: agent.configPath)
        do {
            importCategories = try store.categorizeImport(from: adapter, configPath: configURL)
            importTarget = agent
            showImportReview = true
        } catch {
            // If we can't read the agent file, just skip silently
        }
    }
}
