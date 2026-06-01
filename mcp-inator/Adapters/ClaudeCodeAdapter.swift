import Foundation

struct ClaudeCodeAdapter: AgentAdapter {

    let agentType: AgentType = .claudeCode
    let displayName: String = "Claude Code"

    func defaultConfigPath() -> URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude.json")
    }

    func isInstalled() -> Bool {
        let configFile = defaultConfigPath()                                                // ~/.claude.json
        let claudeDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude")  // ~/.claude/
        return FileManager.default.fileExists(atPath: configFile.path) ||
               FileManager.default.fileExists(atPath: claudeDir.path)
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
        if key == "workspace" {
            return .invalid(reason: "\"workspace\" is reserved by Claude Code CLI and cannot be used as a server name.")
        }
        if !key.matches(pattern: "^[a-z0-9][a-z0-9-]*$") {
            return .invalid(reason: "Server key must start with a letter or digit and contain only a-z, 0-9, or hyphens.")
        }
        return .valid
    }

    // MARK: - Cloud-managed MCPs

    struct CloudManagedMCP: Identifiable {
        let rawName: String
        let displayName: String
        var id: String { rawName }
    }

    func cloudMCPs() -> [CloudManagedMCP] {
        let cacheURL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/mcp-needs-auth-cache.json")
        guard let data = try? Data(contentsOf: cacheURL),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        return dict.keys.sorted().map { name in
            let display = name.hasPrefix("claude.ai ") ? String(name.dropFirst("claude.ai ".count)) : name
            return CloudManagedMCP(rawName: name, displayName: display)
        }
    }
}
