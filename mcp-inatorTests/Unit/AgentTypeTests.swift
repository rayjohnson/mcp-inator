import XCTest
@testable import mcp_inator

final class AgentTypeTests: XCTestCase {

    // MARK: - Creation

    func testInitWithRawValue() {
        let type = AgentType(rawValue: "cursor")
        XCTAssertEqual(type.rawValue, "cursor")
    }

    func testStaticConstantsHaveCorrectRawValues() {
        XCTAssertEqual(AgentType.claudeCode.rawValue, "claude_code")
        XCTAssertEqual(AgentType.claudeDesktop.rawValue, "claude_desktop")
        XCTAssertEqual(AgentType.geminiCLI.rawValue, "gemini_cli")
        XCTAssertEqual(AgentType.codexCLI.rawValue, "codex_cli")
        XCTAssertEqual(AgentType.geminiDesktop.rawValue, "gemini_desktop")
        XCTAssertEqual(AgentType.cursor.rawValue, "cursor")
    }

    // MARK: - Equality and Hashable

    func testEqualityByRawValue() {
        XCTAssertEqual(AgentType(rawValue: "cursor"), AgentType.cursor)
        XCTAssertNotEqual(AgentType(rawValue: "cursor"), AgentType.claudeCode)
    }

    func testUsableInSet() {
        let set: Set<AgentType> = [.claudeCode, .cursor, .claudeCode]
        XCTAssertEqual(set.count, 2)
    }

    func testUsableAsDictionaryKey() {
        let map: [AgentType: String] = [.claudeCode: "a", .cursor: "b"]
        XCTAssertEqual(map[.claudeCode], "a")
        XCTAssertEqual(map[.cursor], "b")
    }

    // MARK: - Codable — must encode as plain string, not {"rawValue":"..."}

    func testEncodesAsPlainString() throws {
        let data = try JSONEncoder().encode(AgentType.claudeCode)
        let decoded = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
        XCTAssertEqual(decoded as? String, "claude_code",
                       "AgentType must encode as its rawValue string, not a keyed object")
    }

    func testDecodesFromPlainString() throws {
        let data = Data("\"gemini_cli\"".utf8)
        let type = try JSONDecoder().decode(AgentType.self, from: data)
        XCTAssertEqual(type, .geminiCLI)
    }

    func testCodableRoundtrip_allKnownTypes() throws {
        let known: [AgentType] = [.claudeCode, .claudeDesktop, .geminiCLI, .codexCLI, .geminiDesktop, .cursor]
        for original in known {
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(AgentType.self, from: data)
            XCTAssertEqual(decoded, original, "\(original.rawValue) failed Codable roundtrip")
        }
    }

    // MARK: - Properties delegate to AdapterRegistry

    func testDisplayName_delegatesToAdapter() {
        XCTAssertEqual(AgentType.claudeCode.displayName, "Claude Code")
        XCTAssertEqual(AgentType.claudeDesktop.displayName, "Claude Desktop")
        XCTAssertEqual(AgentType.geminiCLI.displayName, "Gemini CLI")
        XCTAssertEqual(AgentType.codexCLI.displayName, "Codex CLI")
        XCTAssertEqual(AgentType.geminiDesktop.displayName, "Gemini Desktop")
        XCTAssertEqual(AgentType.cursor.displayName, "Cursor")
    }

    func testIsAppManaged_delegatesToAdapter() {
        XCTAssertFalse(AgentType.claudeCode.isAppManaged)
        XCTAssertFalse(AgentType.claudeDesktop.isAppManaged)
        XCTAssertFalse(AgentType.geminiCLI.isAppManaged)
        XCTAssertFalse(AgentType.codexCLI.isAppManaged)
        XCTAssertTrue(AgentType.geminiDesktop.isAppManaged)
        XCTAssertFalse(AgentType.cursor.isAppManaged)
    }

    func testDefaultConfigPath_containsHomeDirectory() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for type in [AgentType.claudeCode, .claudeDesktop, .geminiCLI, .codexCLI, .geminiDesktop, .cursor] {
            XCTAssertTrue(type.defaultConfigPath.hasPrefix(home),
                          "\(type.rawValue): defaultConfigPath doesn't start with home")
        }
    }

    func testDefaultConfigPath_cursor_endsSuffix() {
        XCTAssertTrue(AgentType.cursor.defaultConfigPath.hasSuffix(".cursor/mcp.json"))
    }

    // MARK: - Unknown type graceful fallback

    func testUnknownType_displayNameFallsBackToRawValue() {
        let ghost = AgentType(rawValue: "ghost_agent_xyz")
        XCTAssertEqual(ghost.displayName, "ghost_agent_xyz")
    }

    func testUnknownType_isAppManagedReturnsFalse() {
        XCTAssertFalse(AgentType(rawValue: "ghost_agent_xyz").isAppManaged)
    }

    func testUnknownType_defaultConfigPathReturnsHome() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(AgentType(rawValue: "ghost_agent_xyz").defaultConfigPath, home)
    }
}
