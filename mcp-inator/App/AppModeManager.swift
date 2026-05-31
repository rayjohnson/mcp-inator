import AppKit
import SwiftUI

// MARK: - Testability Protocol

@MainActor
protocol ActivationPolicyManaging {
    func setPolicy(_ policy: NSApplication.ActivationPolicy)
}

// MARK: - Production Adapter

struct NSAppPolicyManager: ActivationPolicyManaging {
    func setPolicy(_ policy: NSApplication.ActivationPolicy) {
        NSApp.setActivationPolicy(policy)
    }
}

// MARK: - AppModeManager

@MainActor
final class AppModeManager: ObservableObject {
    private let defaults: UserDefaults
    private let policyManager: any ActivationPolicyManaging

    @Published private(set) var showInDock: Bool
    @Published private(set) var isTransitioning: Bool = false

    var openMainWindow: (() -> Void)?
    var closeMainWindow: (() -> Void)?
    var setMenuBarVisible: ((Bool) -> Void)?

    init(
        defaults: UserDefaults = .standard,
        policyManager: (any ActivationPolicyManaging)? = nil
    ) {
        self.defaults = defaults
        self.policyManager = policyManager ?? NSAppPolicyManager()
        self.showInDock = defaults.bool(forKey: "showInDock")
    }

    func setShowInDock(_ enabled: Bool) {
        guard !isTransitioning else { return }
        isTransitioning = true
        showInDock = enabled
        defaults.set(enabled, forKey: "showInDock")
        if enabled {
            policyManager.setPolicy(.regular)
            setMenuBarVisible?(false)
            openMainWindow?()
        } else {
            closeMainWindow?()
            policyManager.setPolicy(.accessory)
            setMenuBarVisible?(true)
        }
        isTransitioning = false
    }
}
