import XCTest
@testable import mcp_inator

// Gemini Desktop-specific tests (isAppManaged identity).
// App-managed no-op behavior is covered by FileBasedAdapterTests.
final class GeminiDesktopAdapterTests: XCTestCase {

    private let adapter = FileBasedAdapter(definition: AdapterRegistry.geminiDesktopDef)

    func testAgentType() {
        XCTAssertEqual(adapter.agentType, .geminiDesktop)
    }

    func testIsAppManaged() {
        XCTAssertTrue(adapter.isAppManaged)
    }
}
