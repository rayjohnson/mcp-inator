import XCTest
@testable import mcp_inator

@MainActor
final class PingServiceTests: XCTestCase {

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        MockURLProtocol.requests = []
        MockURLProtocol.responseStatusCode = 200
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        UserDefaults.standard.removeObject(forKey: "pingHasLaunched")
        UserDefaults.standard.removeObject(forKey: "pingLastActiveDate")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "pingHasLaunched")
        UserDefaults.standard.removeObject(forKey: "pingLastActiveDate")
        super.tearDown()
    }

    // MARK: - PingPreferences

    func testPingPreferences_hasLaunched_defaultsFalse() {
        XCTAssertFalse(PingPreferences.hasLaunched)
    }

    func testPingPreferences_lastActiveDate_defaultsEmpty() {
        XCTAssertEqual(PingPreferences.lastActiveDate, "")
    }

    // MARK: - First-launch gate

    func testFirstLaunch_setsHasLaunchedTrue() async {
        let service = PingService(session: session)
        await service.firePingsIfNeeded()
        XCTAssertTrue(PingPreferences.hasLaunched)
    }

    func testFirstLaunch_sendsFirstLaunchPing() async {
        let service = PingService(session: session)
        await service.firePingsIfNeeded()
        let events = capturedEvents()
        XCTAssertTrue(events.contains("first_launch"), "expected first_launch in \(events)")
    }

    func testFirstLaunch_doesNotFireWhenAlreadyLaunched() async {
        PingPreferences.hasLaunched = true
        PingPreferences.lastActiveDate = todayString()  // suppress daily ping too
        let service = PingService(session: session)
        await service.firePingsIfNeeded()
        let events = capturedEvents()
        XCTAssertFalse(events.contains("first_launch"))
        XCTAssertTrue(MockURLProtocol.requests.isEmpty)
    }

    // MARK: - Daily-active gate

    func testDailyActive_firesWhenNoPreviousDate() async {
        PingPreferences.hasLaunched = true
        let service = PingService(session: session)
        await service.firePingsIfNeeded()
        let events = capturedEvents()
        XCTAssertTrue(events.contains("daily_active"), "expected daily_active in \(events)")
    }

    func testDailyActive_updatesLastActiveDateToToday() async {
        PingPreferences.hasLaunched = true
        let service = PingService(session: session)
        await service.firePingsIfNeeded()
        XCTAssertEqual(PingPreferences.lastActiveDate, todayString())
    }

    func testDailyActive_doesNotFireWhenAlreadyFiredToday() async {
        PingPreferences.hasLaunched = true
        PingPreferences.lastActiveDate = todayString()
        let service = PingService(session: session)
        await service.firePingsIfNeeded()
        XCTAssertTrue(MockURLProtocol.requests.isEmpty)
    }

    func testDailyActive_firesAfterDayChange() async {
        PingPreferences.hasLaunched = true
        PingPreferences.lastActiveDate = "2020-01-01"
        let service = PingService(session: session)
        await service.firePingsIfNeeded()
        let events = capturedEvents()
        XCTAssertTrue(events.contains("daily_active"), "expected daily_active in \(events)")
    }

    // MARK: - Request formation

    func testPingReport_containsSchemaVersionOne() async {
        let service = PingService(session: session)
        await service.firePingsIfNeeded()
        let reports = capturedReports()
        XCTAssertTrue(reports.allSatisfy { $0.schemaVersion == "1" })
    }

    func testPingReport_appVersionIsNotEmpty() async {
        let service = PingService(session: session)
        await service.firePingsIfNeeded()
        let reports = capturedReports()
        XCTAssertFalse(reports.isEmpty)
        XCTAssertTrue(reports.allSatisfy { !$0.appVersion.isEmpty })
    }

    // MARK: - Helpers

    private func capturedEvents() -> [String] {
        capturedReports().map(\.event)
    }

    private func capturedReports() -> [PingReport] {
        MockURLProtocol.requests
            .compactMap(\.httpBody)
            .compactMap { try? JSONDecoder().decode(PingReport.self, from: $0) }
    }

    private func todayString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }
}
