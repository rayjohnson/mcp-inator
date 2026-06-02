import SwiftUI
import AppKit
import Sparkle
import Sentry

// swiftlint:disable:next type_name
struct mcp_inatorApp: App {

    // Set IS_RUNNING_TESTS=YES in the test scheme's environment variables (project.yml).
    // This prevents startup side-effects (agent discovery, window opening) from
    // varying between environments and making coverage non-deterministic.
    static let isRunningTests: Bool = ProcessInfo.processInfo.environment["IS_RUNNING_TESTS"] == "YES"

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appModeManager = AppModeManager()
    @AppStorage("showInDock") private var showInDock = false
    @StateObject private var storeContainer = StoreContainer()
    @StateObject private var registryStore = RegistryStore()
    @StateObject private var catalogStore  = CatalogStore()

    private let sparkleDelegate = SparkleDelegate()
    private let updaterController: SPUStandardUpdaterController

    init() {
        // Record first launch date once; clear session flag so the consent prompt
        // can appear again if eligible.
        if SharingPreferences.firstLaunchDate == nil {
            SharingPreferences.firstLaunchDate = Date()
        }
        SharingPreferences.shownThisSession = false

        SentrySDK.start { options in
            options.dsn = "https://6927130d1d328a2ac1b66594f5d480a2@o4511470552678400.ingest.us.sentry.io/4511470571618304"
            #if DEBUG
            options.environment = "debug"
            #else
            options.environment = "production"
            #endif
        }
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: sparkleDelegate,
            userDriverDelegate: nil
        )
    }

    private let adapters: [any AgentAdapter] = AdapterRegistry.all

    private let discoveryController = DiscoveryWindowController()
    private let aboutController = AboutWindowController()
    private let preferencesController = PreferencesWindowController()
    private let mainWindowController = MainWindowController()
    private let consentController = ConsentWindowController()

    var body: some Scene {
        // isInserted drives status-item presence reactively: false in dock mode removes the
        // NSStatusItem from the menu bar without conditional scene building (which @SceneBuilder
        // does not support in this Xcode version).
        // In test runs, force menu-bar mode (isInserted=true) so the same scene path executes
        // regardless of the developer's showInDock preference.
        MenuBarExtra(isInserted: Binding(get: { !showInDock || mcp_inatorApp.isRunningTests }, set: { _ in })) {
            if let store = storeContainer.store {
                MenuBarView()
                    .environmentObject(store)
                    .environmentObject(registryStore)
                    .environment(\.openAboutWindow, { [aboutController] in
                        Task { @MainActor in
                            aboutController.show(updater: self.updaterController.updater)
                        }
                    })
                    .environment(\.openPreferencesWindow, { [preferencesController, appModeManager] in
                        Task { @MainActor in
                            preferencesController.show(appModeManager: appModeManager)
                        }
                    })
                    .environmentObject(catalogStore)
                    .onAppear {
                        wireWindowController()
                        try? store.seedSelfEntry()
                        Task { await registryStore.populateCategories() }
                        Task { await catalogStore.fetchIfNeeded() }
                        runAgentScan(store: store)
                    }
            } else {
                StoreRecoveryView(error: storeContainer.initError) {
                    storeContainer.reset()
                }
            }
        } label: {
            Image("Inator")
                .onAppear {
                    wireWindowController()
                    Task { await registryStore.populateCategories() }
                    Task { await catalogStore.fetchIfNeeded() }
                    if let store = storeContainer.store { runAgentScan(store: store) }
                }
                // Fires at cold launch (including when isInserted = false) so dock-mode
                // launch gets wireWindowController() called via the scene's view graph.
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.didFinishLaunchingNotification
                )) { _ in
                    wireWindowController()
                }
                // Check consent eligibility each time the app becomes active.
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.didBecomeActiveNotification
                )) { _ in
                    checkSharingEligibility()
                }
                // Reacts when the user toggles dock mode mid-session.
                .onChange(of: showInDock) { newValue in
                    if newValue {
                        appDelegate.insertDockModeMenuItems()
                    }
                }
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About mcp-inator") {
                    Task { @MainActor in
                        aboutController.show(updater: updaterController.updater)
                    }
                }
                Button("Check for Updates...") {
                    updaterController.updater.checkForUpdates()
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Preferences...") {
                    Task { @MainActor in
                        preferencesController.show(appModeManager: appModeManager)
                    }
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

    private func wireWindowController() {
        // Always refresh AppDelegate references — idempotent and needed before any delegate call.
        appDelegate.appModeManager = appModeManager
        appDelegate.aboutController = aboutController
        appDelegate.preferencesController = preferencesController
        appDelegate.updater = updaterController.updater

        guard appModeManager.openMainWindow == nil else { return }
        mainWindowController.configure(
            appModeManager: appModeManager,
            storeContainer: storeContainer,
            registryStore: registryStore,
            catalogStore: catalogStore,
            updater: updaterController.updater,
            aboutController: aboutController
        )
        appModeManager.openMainWindow = { [mainWindowController] in
            mainWindowController.open()
        }
        appModeManager.closeMainWindow = { [mainWindowController] in mainWindowController.close() }
        // If launched with dock mode already set, open the main window.
        // Activation policy and dock-mode menu items are handled by AppDelegate.applicationDidFinishLaunching.
        // Skip in test runs: IS_RUNNING_TESTS=YES forces menu-bar mode via -showInDock NO launch arg,
        // but guard here too so window state never varies across test environments.
        if showInDock && !mcp_inatorApp.isRunningTests {
            mainWindowController.open()
        }
    }

    // MARK: - Sharing Consent Eligibility

    private func checkSharingEligibility() {
        guard !mcp_inatorApp.isRunningTests else { return }
        Task { @MainActor in
            await UsageSharingService.shared.flushPendingIfNeeded()
        }
        guard !SharingPreferences.consented,
              !SharingPreferences.shownThisSession,
              let firstLaunch = SharingPreferences.firstLaunchDate,
              let daysSince = Calendar.current.dateComponents([.day], from: firstLaunch, to: Date()).day,
              daysSince > 7,
              let store = storeContainer.store,
              store.configs.filter({ !$0.isPrivate }).count >= 1 else { return }

        SharingPreferences.shownThisSession = true
        SharingPreferences.consentShownAt = Date()
        consentController.show(servers: storeContainer.store?.configs ?? [])
    }

    // MARK: - Agent Scan (FR-019, T031, T032)

    private func runAgentScan(store: ConfigStore) {
        guard !mcp_inatorApp.isRunningTests else { return }
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

// MARK: - MainWindowController

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private weak var appModeManager: AppModeManager?
    private weak var storeContainer: StoreContainer?
    private weak var registryStore: RegistryStore?
    private weak var catalogStore: CatalogStore?
    private var updater: SPUUpdater?
    private weak var aboutController: AboutWindowController?

    // swiftlint:disable:next function_parameter_count
    func configure(
        appModeManager: AppModeManager,
        storeContainer: StoreContainer,
        registryStore: RegistryStore,
        catalogStore: CatalogStore,
        updater: SPUUpdater,
        aboutController: AboutWindowController
    ) {
        self.appModeManager = appModeManager
        self.storeContainer = storeContainer
        self.registryStore = registryStore
        self.catalogStore = catalogStore
        self.updater = updater
        self.aboutController = aboutController
    }

    func open() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let appModeManager,
              let storeContainer,
              let registryStore,
              let catalogStore,
              let updater,
              let aboutController else { return }

        let view = MainWindowView()
            .environmentObject(appModeManager)
            .environmentObject(storeContainer)
            .environmentObject(registryStore)
            .environmentObject(catalogStore)
            .environment(\.openAboutWindow, { [weak aboutController] in
                Task { @MainActor in
                    aboutController?.show(updater: updater)
                }
            })

        let hosting = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hosting)
        win.title = "mcp-inator"
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.setContentSize(NSSize(width: 960, height: 620))
        win.minSize = NSSize(width: 800, height: 500)
        win.setFrameAutosaveName("main")
        win.isReleasedWhenClosed = false
        win.delegate = self
        // T021: Recover if saved position is off-screen (e.g. after monitor disconnect)
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(win.frame) }
        if !onScreen { win.center() }
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        // If still in dock mode, quitting is handled by AppDelegate
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
        let discoveryWindow = NSWindow(contentViewController: hosting)
        discoveryWindow.title = "New Agents Found"
        discoveryWindow.setContentSize(NSSize(width: 440, height: 380))
        discoveryWindow.styleMask = [.titled, .closable]
        discoveryWindow.center()
        discoveryWindow.isReleasedWhenClosed = false
        discoveryWindow.delegate = self
        discoveryWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = discoveryWindow
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

// MARK: - OpenPreferencesWindowKey

private struct OpenPreferencesWindowKey: EnvironmentKey {
    static let defaultValue: @Sendable () -> Void = {}
}

extension EnvironmentValues {
    var openPreferencesWindow: @Sendable () -> Void {
        get { self[OpenPreferencesWindowKey.self] }
        set { self[OpenPreferencesWindowKey.self] = newValue }
    }
}

// MARK: - NavigationIsCompactKey
// True in the 420px menu bar popover (push navigation); false in the dock-mode
// split window (tap-to-select). Detail views read this to decide whether to
// render an explicit back button.

private struct NavigationIsCompactKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var navigationIsCompact: Bool {
        get { self[NavigationIsCompactKey.self] }
        set { self[NavigationIsCompactKey.self] = newValue }
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

// MARK: - PreferencesWindowController

@MainActor
final class PreferencesWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(appModeManager: AppModeManager) {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = PreferencesView()
            .environmentObject(appModeManager)
        let hosting = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hosting)
        win.styleMask = [.titled, .closable]
        win.title = "Preferences"
        win.setContentSize(NSSize(width: 400, height: 150))
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

// MARK: - ConsentWindowController

@MainActor
final class ConsentWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(servers: [MCPServerConfig]) {
        guard window == nil else { return }

        let view = SharingConsentView(
            servers: servers,
            onDismiss: { [weak self] in self?.window?.close() }
        )
        let hosting = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hosting)
        win.title = "Help improve mcp-inator"
        win.styleMask = [.titled, .closable]
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
