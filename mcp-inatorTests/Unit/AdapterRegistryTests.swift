import XCTest
@testable import mcp_inator

final class AdapterRegistryTests: XCTestCase {

    // MARK: - Structural consistency

    func testDefinitionsAndAdaptersHaveSameCount() {
        XCTAssertEqual(AdapterRegistry.definitions.count, AdapterRegistry.all.count)
    }

    func testNoDuplicateAgentTypesInDefinitions() {
        let types = AdapterRegistry.definitions.map(\.agentType.rawValue)
        XCTAssertEqual(types.count, Set(types).count, "Duplicate agent type in definitions")
    }

    func testNoDuplicateAgentTypesInAdapters() {
        let types = AdapterRegistry.all.map(\.agentType.rawValue)
        XCTAssertEqual(types.count, Set(types).count, "Duplicate agent type in adapters")
    }

    func testDefinitionTypesAndAdapterTypesMatch() {
        let defTypes = Set(AdapterRegistry.definitions.map(\.agentType.rawValue))
        let adapterTypes = Set(AdapterRegistry.all.map(\.agentType.rawValue))
        XCTAssertEqual(defTypes, adapterTypes, "Definition types and adapter types diverged")
    }

    // MARK: - Lookup correctness

    func testAdapterLookup_knownTypes() {
        let known: [AgentType] = [.claudeCode, .claudeDesktop, .geminiCLI, .codexCLI, .geminiDesktop, .cursor]
        for type in known {
            XCTAssertNotNil(AdapterRegistry.adapter(for: type), "Missing adapter for \(type.rawValue)")
        }
    }

    func testDefinitionLookup_knownTypes() {
        let known: [AgentType] = [.claudeCode, .claudeDesktop, .geminiCLI, .codexCLI, .geminiDesktop, .cursor]
        for type in known {
            XCTAssertNotNil(AdapterRegistry.definition(for: type), "Missing definition for \(type.rawValue)")
        }
    }

    func testLookup_unknownType_returnsNil() {
        let ghost = AgentType(rawValue: "nonexistent_agent_xyz")
        XCTAssertNil(AdapterRegistry.adapter(for: ghost))
        XCTAssertNil(AdapterRegistry.definition(for: ghost))
    }

    // MARK: - Definition field completeness

    func testAllDefinitionsHaveNonEmptyRequiredFields() {
        for def in AdapterRegistry.definitions {
            let id = def.agentType.rawValue
            XCTAssertFalse(def.displayName.isEmpty, "\(id): empty displayName")
            XCTAssertFalse(def.configPathRelative.isEmpty, "\(id): empty configPathRelative")
            XCTAssertFalse(def.mcpKey.isEmpty, "\(id): empty mcpKey")
            XCTAssertFalse(def.icon.fallback.letter.isEmpty, "\(id): empty fallback letter")
        }
    }

    func testConfigPathRelativeDoesNotStartWithSlashOrTilde() {
        for def in AdapterRegistry.definitions {
            XCTAssertFalse(def.configPathRelative.hasPrefix("/"),
                           "\(def.agentType.rawValue): configPathRelative should not start with /")
            XCTAssertFalse(def.configPathRelative.hasPrefix("~"),
                           "\(def.agentType.rawValue): configPathRelative should not start with ~")
        }
    }

    func testDefinitionDisplayNamesMatchAdapterDisplayNames() {
        for def in AdapterRegistry.definitions {
            guard let adapter = AdapterRegistry.adapter(for: def.agentType) else { continue }
            XCTAssertEqual(def.displayName, adapter.displayName,
                           "\(def.agentType.rawValue): definition/adapter displayName mismatch")
        }
    }

    // MARK: - App-managed semantics

    func testGeminiDesktop_isAppManaged() {
        XCTAssertTrue(AdapterRegistry.adapter(for: .geminiDesktop)?.isAppManaged == true)
        XCTAssertTrue(AdapterRegistry.definition(for: .geminiDesktop)?.isAppManaged == true)
    }

    func testOtherAgents_areNotAppManaged() {
        let fileBasedAgents: [AgentType] = [.claudeCode, .claudeDesktop, .geminiCLI, .codexCLI, .cursor]
        for type in fileBasedAgents {
            XCTAssertFalse(AdapterRegistry.adapter(for: type)?.isAppManaged ?? false,
                           "\(type.rawValue) should not be app-managed")
        }
    }

    // MARK: - All adapters produce a defaultConfigPath

    func testAllAdaptersReturnNonEmptyDefaultConfigPath() {
        for adapter in AdapterRegistry.all {
            XCTAssertFalse(adapter.defaultConfigPath().path.isEmpty,
                           "\(adapter.agentType.rawValue): empty defaultConfigPath")
        }
    }

    // MARK: - isInstalled does not crash

    func testIsInstalledDoesNotCrashForAnyAdapter() {
        for adapter in AdapterRegistry.all {
            _ = adapter.isInstalled()
        }
    }
}
