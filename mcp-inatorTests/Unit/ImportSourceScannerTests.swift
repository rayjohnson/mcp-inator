import XCTest
@testable import mcp_inator

final class ImportSourceScannerTests: XCTestCase {

    // MARK: - Helpers

    private func makeScanner(
        adapters: [any AgentAdapter],
        existingPaths: Set<String> = []
    ) -> ImportSourceScanner {
        ImportSourceScanner(adapters: adapters, fileExists: { existingPaths.contains($0.path) })
    }

    private func stub(
        type: AgentType = .claudeDesktop,
        displayName: String = "Stub",
        installed: Bool = true,
        appManaged: Bool = false,
        configPath: URL = URL(fileURLWithPath: "/config/stub.json")
    ) -> StubAdapter {
        let s = StubAdapter(agentType: type, displayName: displayName, configPath: configPath)
        s.installedResult = installed
        s.appManagedResult = appManaged
        return s
    }

    // MARK: - Construction rules

    func testScan_notInstalled_excluded() {
        let adapter = stub(installed: false)
        let results = makeScanner(adapters: [adapter], existingPaths: [adapter.configPathResult.path]).scan()
        XCTAssertTrue(results.isEmpty)
    }

    func testScan_installedFileBacked_configMissing_excluded() {
        let adapter = stub(installed: true, appManaged: false)
        let results = makeScanner(adapters: [adapter], existingPaths: []).scan()
        XCTAssertTrue(results.isEmpty)
    }

    func testScan_installedFileBacked_configExists_isImportable() {
        let adapter = stub(installed: true, appManaged: false)
        let results = makeScanner(adapters: [adapter], existingPaths: [adapter.configPathResult.path]).scan()
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].isImportable)
        XCTAssertNil(results[0].unavailableReason)
        XCTAssertEqual(results[0].agentType, adapter.agentType)
    }

    func testScan_installedAppManaged_notImportable_withReason() {
        let adapter = stub(installed: true, appManaged: true, configPath: URL(fileURLWithPath: "/no/file"))
        let results = makeScanner(adapters: [adapter], existingPaths: []).scan()
        XCTAssertEqual(results.count, 1)
        XCTAssertFalse(results[0].isImportable)
        XCTAssertNotNil(results[0].unavailableReason)
    }

    func testScan_installedAppManaged_notInstalled_excluded() {
        let adapter = stub(installed: false, appManaged: true)
        let results = makeScanner(adapters: [adapter]).scan()
        XCTAssertTrue(results.isEmpty)
    }

    func testScan_mixedAdapters_returnsCorrectSubset() {
        let configPath = "/config/valid.json"
        let importable = stub(type: .claudeDesktop, displayName: "Claude Desktop", installed: true, appManaged: false, configPath: URL(fileURLWithPath: configPath))
        let managed = stub(type: .geminiDesktop, displayName: "Gemini Desktop", installed: true, appManaged: true)
        let notInstalled = stub(type: .claudeCode, displayName: "Claude Code", installed: false)
        let missingConfig = stub(type: .geminiCLI, displayName: "Gemini CLI", installed: true, appManaged: false, configPath: URL(fileURLWithPath: "/no/config.json"))

        let results = makeScanner(adapters: [importable, managed, notInstalled, missingConfig], existingPaths: [configPath]).scan()

        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.contains(where: { $0.agentType == .claudeDesktop && $0.isImportable }))
        XCTAssertTrue(results.contains(where: { $0.agentType == .geminiDesktop && !$0.isImportable }))
    }

    func testScan_allExcluded_returnsEmpty() {
        let notInstalled = stub(installed: false)
        let missingConfig = stub(type: .claudeCode, installed: true, appManaged: false)
        let results = makeScanner(adapters: [notInstalled, missingConfig], existingPaths: []).scan()
        XCTAssertTrue(results.isEmpty)
    }

    func testScan_unavailableReason_containsDisplayName() {
        let name = "Fancy Agent"
        let adapter = stub(displayName: name, installed: true, appManaged: true)
        let results = makeScanner(adapters: [adapter]).scan()
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].unavailableReason?.contains(name) == true)
    }

    func testScan_configPath_propagatedToSource() {
        let path = URL(fileURLWithPath: "/some/specific/path.json")
        let adapter = stub(installed: true, appManaged: false, configPath: path)
        let results = makeScanner(adapters: [adapter], existingPaths: [path.path]).scan()
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].configPath, path)
    }
}
