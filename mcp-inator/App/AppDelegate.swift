import AppKit
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var appModeManager: AppModeManager?
    weak var aboutController: AboutWindowController?
    weak var preferencesController: PreferencesWindowController?
    var updater: SPUUpdater?
    var launchAction: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        launchAction?()
        launchAction = nil
        if UserDefaults.standard.bool(forKey: "showInDock") {
            NSApp.setActivationPolicy(.regular)
            insertDockModeMenuItems()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool {
        appModeManager?.showInDock ?? false
    }

    // Intercepts the system "About mcp-inator" menu item in dock mode.
    @objc func orderFrontStandardAboutPanel(_ sender: Any?) {
        guard let updater else { return }
        Task { @MainActor in aboutController?.show(updater: updater) }
    }

    // Responds to Preferences… / Cmd+, in dock mode.
    @objc func openPreferences(_ sender: Any?) {
        guard let appModeManager else { return }
        Task { @MainActor in preferencesController?.show(appModeManager: appModeManager) }
    }

    // Responds to Check for Updates… in dock mode.
    @objc func checkForUpdatesFromMenu(_ sender: Any?) {
        updater?.checkForUpdates()
    }

    // Adds dock-mode-specific items to the Application menu.
    // Safe to call multiple times (idempotent).
    func insertDockModeMenuItems() {
        guard let appMenu = NSApp.mainMenu?.item(at: 0)?.submenu else { return }
        guard appMenu.item(withTitle: "Preferences...") == nil else { return }

        let updatesItem = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(checkForUpdatesFromMenu),
            keyEquivalent: ""
        )
        updatesItem.target = self
        appMenu.insertItem(updatesItem, at: 1)
        appMenu.insertItem(.separator(), at: 2)

        let prefsItem = NSMenuItem(
            title: "Preferences...",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        prefsItem.keyEquivalentModifierMask = .command
        prefsItem.target = self
        appMenu.insertItem(prefsItem, at: 3)
        appMenu.insertItem(.separator(), at: 4)
    }
}
