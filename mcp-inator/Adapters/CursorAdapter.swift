import Foundation

struct CursorAdapter: AgentAdapter {

    let agentType: AgentType = .cursor
    let displayName: String = "Cursor"

    func defaultConfigPath() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/mcp.json")
    }

    func isInstalled() -> Bool {
        let path = defaultConfigPath()
        return FileManager.default.fileExists(atPath: path.path) ||
               FileManager.default.fileExists(atPath: path.deletingLastPathComponent().path)
    }

    func readConfigs(from path: URL) throws -> [String: MCPServerConfig] {
        let json = try JSONAdapterHelper.readFullJSON(from: path)
        let serverDict = json["mcpServers"] as? [String: Any] ?? [:]
        return JSONAdapterHelper.parseMCPConfigs(from: serverDict)
    }

    func writeConfigs(
        _ configs: [String: MCPServerConfig],
        to path: URL,
        expectedExisting: [String: MCPServerConfig]?
    ) throws -> WriteResult {
        try JSONAdapterHelper.writeConfigs(
            configs, to: path,
            expectedExisting: expectedExisting,
            mcpKey: "mcpServers"
        )
    }

    func removeConfig(key: String, from path: URL, expectedValue: MCPServerConfig?) throws -> WriteResult {
        try JSONAdapterHelper.removeConfig(
            key: key, from: path,
            expectedValue: expectedValue,
            mcpKey: "mcpServers"
        )
    }

    func validateServerKey(_ key: String) -> KeyValidationResult {
        if !key.matches(pattern: "^[a-z0-9][a-z0-9-]*$") {
            return .invalid(reason: "Server key must start with a letter or digit and contain only a-z, 0-9, or hyphens.")
        }
        return .valid
    }
}
