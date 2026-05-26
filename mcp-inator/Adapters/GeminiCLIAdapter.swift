import Foundation

struct GeminiCLIAdapter: AgentAdapter {

    let agentType: AgentType = .geminiCLI
    let displayName: String = "Gemini CLI"

    func defaultConfigPath() -> URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".gemini/settings.json")
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

    // Gemini rejects underscores in server key names (research.md R-001)
    func validateServerKey(_ key: String) -> KeyValidationResult {
        if key.contains("_") {
            return .invalid(reason: "Gemini CLI does not allow underscores in server names. Use hyphens instead.")
        }
        if !key.matches(pattern: "^[a-z0-9][a-z0-9-]*$") {
            return .invalid(reason: "Server key must start with a letter or digit and contain only a-z, 0-9, or hyphens.")
        }
        return .valid
    }
}
