import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var appModeManager: AppModeManager?

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool {
        appModeManager?.showInDock ?? false
    }
}
