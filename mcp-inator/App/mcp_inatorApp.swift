import SwiftUI
import Sparkle

@main
struct mcp_inatorApp: App {

    @StateObject private var storeContainer = StoreContainer()
    @State private var showDiscovery = false
    @State private var discoveredAgents: [ConfigStore.DiscoveryResult] = []

    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    private let adapters: [any AgentAdapter] = [
        ClaudeCodeAdapter(),
        ClaudeDesktopAdapter(),
        GeminiCLIAdapter(),
        CodexCLIAdapter()
    ]

    var body: some Scene {
        MenuBarExtra("mcp-inator", systemImage: "server.rack") {
            if let store = storeContainer.store {
                MenuBarView()
                    .environmentObject(store)
                    .onAppear { runAgentScan(store: store) }
                    .sheet(isPresented: $showDiscovery) {
                        DiscoveryView(results: discoveredAgents)
                            .environmentObject(store)
                    }
            } else {
                StoreRecoveryView(error: storeContainer.initError) {
                    storeContainer.reset()
                }
            }
        }
        .menuBarExtraStyle(.window)
    }

    // MARK: - Agent Scan (FR-019, T031, T032)

    private func runAgentScan(store: ConfigStore) {
        Task { @MainActor in
            do {
                let results = try store.discoverAgents(adapters: adapters)
                let newlyFound = results.filter(\.isNew)
                if !newlyFound.isEmpty {
                    discoveredAgents = newlyFound
                    showDiscovery = true
                }
            } catch {
                // Discovery errors are non-fatal
            }
        }
    }
}

// MARK: - StoreContainer (FR-028: recoverable init)

@MainActor
final class StoreContainer: ObservableObject {
    @Published private(set) var store: ConfigStore?
    @Published private(set) var initError: Error?

    init() { tryInit() }

    func reset() {
        initError = nil
        tryInit()
    }

    private func tryInit() {
        do {
            store = try ConfigStore()
        } catch {
            store = nil
            initError = error
        }
    }
}

// MARK: - StoreRecoveryView (FR-028)

private struct StoreRecoveryView: View {
    let error: Error?
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 40))
                .foregroundColor(.red)
            Text("Config library not found")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Your previous config library could not be opened. This may happen after a system migration or disk error.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            if let err = error {
                Text(err.localizedDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
            Button("Start Fresh") { onRetry() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(width: 360, height: 280)
    }
}
