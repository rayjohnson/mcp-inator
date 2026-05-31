import Foundation
import AppKit

// Generic AgentAdapter for JSON-based agents (and app-managed agents).
// Behavior is fully driven by an AgentDefinition — adding a new agent
// requires only a new definition in AdapterRegistry, no code changes here.
struct FileBasedAdapter: AgentAdapter {
    let definition: AgentDefinition

    var agentType: AgentType { definition.agentType }
    var displayName: String { definition.displayName }
    var isAppManaged: Bool { definition.isAppManaged }

    func defaultConfigPath() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(definition.configPathRelative)
    }

    func isInstalled() -> Bool {
        if definition.isAppManaged {
            for bid in definition.icon.bundleIds
            where NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) != nil {
                return true
            }
            for path in definition.icon.appPaths
            where FileManager.default.fileExists(atPath: path) {
                return true
            }
            return false
        }
        let path = defaultConfigPath()
        return FileManager.default.fileExists(atPath: path.path) ||
               FileManager.default.fileExists(atPath: path.deletingLastPathComponent().path)
    }

    func readConfigs(from path: URL) throws -> [String: MCPServerConfig] {
        guard !definition.isAppManaged else { return [:] }
        let json = try JSONAdapterHelper.readFullJSON(from: path)
        let serverDict = json[definition.mcpKey] as? [String: Any] ?? [:]
        return JSONAdapterHelper.parseMCPConfigs(from: serverDict)
    }

    func writeConfigs(
        _ configs: [String: MCPServerConfig],
        to path: URL,
        expectedExisting: [String: MCPServerConfig]?
    ) throws -> WriteResult {
        guard !definition.isAppManaged else { return .success }
        return try JSONAdapterHelper.writeConfigs(
            configs, to: path,
            expectedExisting: expectedExisting,
            mcpKey: definition.mcpKey
        )
    }

    func removeConfig(key: String, from path: URL, expectedValue: MCPServerConfig?) throws -> WriteResult {
        guard !definition.isAppManaged else { return .success }
        return try JSONAdapterHelper.removeConfig(
            key: key, from: path,
            expectedValue: expectedValue,
            mcpKey: definition.mcpKey
        )
    }

    func validateServerKey(_ key: String) -> KeyValidationResult {
        guard !definition.isAppManaged else { return .valid }
        let validation = definition.keyValidation
        for word in validation.reservedWords where key == word {
            return .invalid(reason: "\"\(word)\" is reserved and cannot be used as a server name.")
        }
        if validation.rejectUnderscores && key.contains("_") {
            return .invalid(reason: "\(definition.displayName) does not allow underscores in server names. Use hyphens instead.")
        }
        if !key.matches(pattern: validation.pattern) {
            return .invalid(reason: validation.errorMessage)
        }
        return .valid
    }
}
