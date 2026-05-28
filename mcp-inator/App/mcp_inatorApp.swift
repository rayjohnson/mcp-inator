import SwiftUI
import AppKit
import Sparkle

// swiftlint:disable:next type_name
struct mcp_inatorApp: App {

    @StateObject private var storeContainer = StoreContainer()
    @StateObject private var registryStore = RegistryStore()

    private let sparkleDelegate = SparkleDelegate()
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: sparkleDelegate,
            userDriverDelegate: nil
        )
    }

    private let adapters: [any AgentAdapter] = [
        ClaudeCodeAdapter(),
        ClaudeDesktopAdapter(),
        GeminiCLIAdapter(),
        CodexCLIAdapter(),
        GeminiDesktopAdapter()
    ]

    private let discoveryController = DiscoveryWindowController()
    private let aboutController = AboutWindowController()

    var body: some Scene {
        MenuBarExtra {
            if let store = storeContainer.store {
                MenuBarView()
                    .environmentObject(store)
                    .environmentObject(registryStore)
                    .environment(\.openAboutWindow, { [aboutController] in
                        Task { @MainActor in
                            aboutController.show(updater: self.updaterController.updater)
                        }
                    })
                    .onAppear {
                        try? store.seedSelfEntry()
                        Task { await registryStore.populateCategories() }
                        runAgentScan(store: store)
                    }
            } else {
                StoreRecoveryView(error: storeContainer.initError) {
                    storeContainer.reset()
                }
            }
        } label: {
            Image("Inator")
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

// MARK: - OpenAboutWindowKey

private struct OpenAboutWindowKey: EnvironmentKey {
    static let defaultValue: @Sendable () -> Void = {}
}

extension EnvironmentValues {
    var openAboutWindow: @Sendable () -> Void {
        get { self[OpenAboutWindowKey.self] }
        set { self[OpenAboutWindowKey.self] = newValue }
    }
}

// MARK: - AboutWindowController

@MainActor
final class AboutWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(updater: SPUUpdater) {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: AboutView(updater: updater))
        let win = NSWindow(contentViewController: hosting)
        win.styleMask = [.titled, .closable]
        win.title = "About mcp-inator"
        win.setContentSize(NSSize(width: 380, height: 260))
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

// MARK: - SparkleDelegate

/// Strips the Gatekeeper quarantine flag from Sparkle's staging cache before the
/// update is installed, so the unsigned app can relaunch without user intervention.
/// Must target the Sparkle cache (not Bundle.main), because `willInstallUpdate` fires
/// before the new bundle replaces the running one — stripping the running bundle has
/// no effect on the freshly-downloaded replacement.
final class SparkleDelegate: NSObject, SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        let fm = FileManager.default
        var pathsToStrip: [String] = []

        if let bundleID = Bundle.main.bundleIdentifier,
           let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let sparkleCachePath = caches
                .appendingPathComponent(bundleID)
                .appendingPathComponent("org.sparkle-project.Sparkle")
                .path
            if fm.fileExists(atPath: sparkleCachePath) {
                pathsToStrip.append(sparkleCachePath)
            }
        }

        for path in pathsToStrip {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            process.arguments = ["-dr", "com.apple.quarantine", path]
            try? process.run()
            process.waitUntilExit()
        }
    }
}
