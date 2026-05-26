import SwiftUI
import AppKit
import Sparkle

// swiftlint:disable:next type_name
struct mcp_inatorApp: App {

    @StateObject private var storeContainer = StoreContainer()
    @StateObject private var catalogStore = CatalogStore()

    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    private let adapters: [any AgentAdapter] = [
        ClaudeCodeAdapter(),
        ClaudeDesktopAdapter(),
        GeminiCLIAdapter(),
        CodexCLIAdapter(),
        GeminiDesktopAdapter()
    ]

    private let discoveryController = DiscoveryWindowController()

    var body: some Scene {
        MenuBarExtra {
            if let store = storeContainer.store {
                MenuBarView()
                    .environmentObject(store)
                    .environmentObject(catalogStore)
                    .onAppear {
                        catalogStore.load()
                        try? store.seedSelfEntry()
                        runAgentScan(store: store)
                    }
            } else {
                StoreRecoveryView(error: storeContainer.initError) {
                    storeContainer.reset()
                }
            }
        } label: {
            if let url = Bundle.main.url(forResource: "Inator", withExtension: "png"),
               let nsImage = NSImage(contentsOf: url) {
                let _ = { nsImage.isTemplate = true }()
                Image(nsImage: nsImage)
            } else {
                Image(systemName: "server.rack")
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
                    discoveryController.show(results: newlyFound, store: store)
                }
            } catch {
                // Discovery errors are non-fatal
            }
        }
    }
}

// MARK: - DiscoveryWindowController

@MainActor
final class DiscoveryWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(results: [ConfigStore.DiscoveryResult], store: ConfigStore) {
        guard window == nil else { return }

        let view = DiscoveryView(results: results, onDismiss: { [weak self] in
            self?.window?.close()
        }).environmentObject(store)

        let hosting = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: hosting)
        w.title = "New Agents Found"
        w.setContentSize(NSSize(width: 440, height: 380))
        w.styleMask = [.titled, .closable]
        w.center()
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = w
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
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
