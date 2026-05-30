import XCTest
@testable import mcp_inator

@MainActor
final class AppModeManagerTests: XCTestCase {

    // MARK: - Mocks

    final class MockPolicyManager: ActivationPolicyManaging {
        var lastPolicy: NSApplication.ActivationPolicy?
        var callCount = 0

        func setPolicy(_ policy: NSApplication.ActivationPolicy) {
            lastPolicy = policy
            callCount += 1
        }
    }

    // MARK: - Helpers

    private func makeManager(
        defaults: UserDefaults? = nil,
        policyManager: MockPolicyManager = MockPolicyManager()
    ) -> (AppModeManager, MockPolicyManager) {
        // swiftlint:disable:next force_unwrapping
        let suite = UserDefaults(suiteName: UUID().uuidString)!
        let mgr = AppModeManager(
            defaults: defaults ?? suite,
            policyManager: policyManager
        )
        return (mgr, policyManager)
    }

    // MARK: - Tests

    func testSetShowInDockTrue_setsPublishedValueAndCallsPolicy() {
        let (mgr, policy) = makeManager()
        var openCalled = false
        mgr.openMainWindow = { openCalled = true }

        mgr.setShowInDock(true)

        XCTAssertTrue(mgr.showInDock)
        XCTAssertEqual(policy.lastPolicy, .regular)
        XCTAssertTrue(openCalled)
    }

    func testSetShowInDockFalse_setsPublishedValueAndCallsPolicy() {
        // swiftlint:disable:next force_unwrapping
        let suite = UserDefaults(suiteName: UUID().uuidString)!
        suite.set(true, forKey: "showInDock")
        let policy = MockPolicyManager()
        let mgr = AppModeManager(defaults: suite, policyManager: policy)
        var closeCalled = false
        mgr.closeMainWindow = { closeCalled = true }

        mgr.setShowInDock(false)

        XCTAssertFalse(mgr.showInDock)
        XCTAssertEqual(policy.lastPolicy, .accessory)
        XCTAssertTrue(closeCalled)
    }

    func testShowInDock_persistsAcrossReinit() {
        // swiftlint:disable:next force_unwrapping
        let suite = UserDefaults(suiteName: UUID().uuidString)!
        let mgr1 = AppModeManager(defaults: suite)
        mgr1.openMainWindow = {}
        mgr1.setShowInDock(true)

        let mgr2 = AppModeManager(defaults: suite)
        XCTAssertTrue(mgr2.showInDock)
    }

    func testRapidToggle_leavesShowInDockMatchingLastCall() {
        let (mgr, _) = makeManager()
        mgr.openMainWindow = {}
        mgr.closeMainWindow = {}

        for i in 0..<20 {
            mgr.setShowInDock(i.isMultiple(of: 2))
        }

        XCTAssertFalse(mgr.showInDock)
    }

    func testCloseCalledBeforePolicyOnDisable() {
        // swiftlint:disable:next force_unwrapping
        let suite = UserDefaults(suiteName: UUID().uuidString)!
        suite.set(true, forKey: "showInDock")

        final class OrderLog { var events: [String] = [] }
        let log = OrderLog()

        final class OrderedPolicyManager: ActivationPolicyManaging {
            let log: OrderLog
            init(_ log: OrderLog) { self.log = log }
            func setPolicy(_ policy: NSApplication.ActivationPolicy) {
                if policy == .accessory { log.events.append("policy") }
            }
        }

        let mgr = AppModeManager(defaults: suite, policyManager: OrderedPolicyManager(log))
        mgr.closeMainWindow = { log.events.append("close") }
        mgr.setShowInDock(false)

        XCTAssertEqual(log.events, ["close", "policy"], "closeMainWindow must precede setPolicy(.accessory)")
    }
}
