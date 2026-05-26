import Foundation
import MCP

// MARK: - MCPTools

enum MCPTools {

    // MARK: - Tool Definitions

    static var allTools: [Tool] {
        [
            Tool(
                name: "list_servers",
                description: "List all MCP server configurations in the mcp-inator library.",
                inputSchema: .object(["type": "object", "properties": .object([:]), "required": .array([])])
            ),
            Tool(
                name: "add_server",
                description: "Add a new stdio MCP server configuration to the library.",
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "name":    .object(["type": "string", "description": "Display name (e.g. 'Playwright')"]),
                        "command": .object(["type": "string", "description": "Executable path or name (e.g. 'npx')"]),
                        "args":    .object(["type": "array", "items": .object(["type": "string"]), "description": "CLI arguments"]),
                        "env":     .object(["type": "object", "additionalProperties": .object(["type": "string"]), "description": "Environment variables"])
                    ]),
                    "required": .array(["name", "command"])
                ])
            ),
            Tool(
                name: "remove_server",
                description: "Remove a server configuration from the library. Cannot remove the built-in 'mcp-inator' entry.",
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "server_name": .object(["type": "string", "description": "serverKey of the server to remove"])
                    ]),
                    "required": .array(["server_name"])
                ])
            ),
            Tool(
                name: "enable_server",
                description: "Enable a server for a specific agent by writing it to the agent's config file.",
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "server_name": .object(["type": "string", "description": "serverKey of the server"]),
                        "agent":       .object(["type": "string", "description": "Agent identifier: claude_code, claude_desktop, gemini_cli, codex_cli, gemini_desktop"])
                    ]),
                    "required": .array(["server_name", "agent"])
                ])
            ),
            Tool(
                name: "disable_server",
                description: "Disable a server for a specific agent by removing it from the agent's config file.",
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "server_name": .object(["type": "string", "description": "serverKey of the server"]),
                        "agent":       .object(["type": "string", "description": "Agent identifier: claude_code, claude_desktop, gemini_cli, codex_cli, gemini_desktop"])
                    ]),
                    "required": .array(["server_name", "agent"])
                ])
            ),
            Tool(
                name: "list_agents",
                description: "List all discovered AI agents and their current availability.",
                inputSchema: .object(["type": "object", "properties": .object([:]), "required": .array([])])
            )
        ]
    }

    // MARK: - Dispatch

    @MainActor
    static func dispatch(store: ConfigStore, params: CallTool.Parameters) async -> CallTool.Result {
        let args = params.arguments ?? [:]
        switch params.name {
        case "list_servers":   return listServers(store: store)
        case "add_server":     return await addServer(store: store, args: args)
        case "remove_server":  return await removeServer(store: store, args: args)
        case "enable_server":  return await enableServer(store: store, args: args)
        case "disable_server": return await disableServer(store: store, args: args)
        case "list_agents":    return listAgents(store: store)
        default:
            return toolError("Unknown tool: '\(params.name)'")
        }
    }

    // MARK: - list_servers

    @MainActor
    private static func listServers(store: ConfigStore) -> CallTool.Result {
        struct ServerSummary: Encodable {
            let serverKey: String
            let displayName: String
            let command: String
            let args: [String]
            let transportType: String
            let url: String
        }
        let summaries = store.configs.map { c in
            ServerSummary(
                serverKey: c.serverKey,
                displayName: c.displayName,
                command: c.command,
                args: c.args,
                transportType: c.transportType.rawValue,
                url: c.url
            )
        }
        guard let data = try? JSONEncoder().encode(summaries),
              let json = String(data: data, encoding: .utf8) else {
            return toolError("Failed to serialize server list")
        }
        return CallTool.Result(content: [.text(text: json, annotations: nil, _meta: nil)], isError: nil)
    }

    // MARK: - add_server

    @MainActor
    private static func addServer(store: ConfigStore, args: [String: Value]) async -> CallTool.Result {
        guard let name = args["name"]?.stringValue, !name.isEmpty else {
            return toolError("Missing required argument: 'name'")
        }
        guard let command = args["command"]?.stringValue, !command.isEmpty else {
            return toolError("Missing required argument: 'command'")
        }
        let cliArgs: [String] = args["args"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let envVars: [EnvVar] = args["env"]?.objectValue?.sorted(by: { $0.key < $1.key })
            .map { EnvVar(key: $0.key, value: $0.value.stringValue ?? "") } ?? []

        let serverKey = MCPServerConfig.generateKey(from: name)
        if store.configs.contains(where: { $0.serverKey == serverKey }) {
            return toolError("server '\(serverKey)' already exists")
        }

        let config = MCPServerConfig(
            displayName: name,
            serverKey: serverKey,
            command: command,
            args: cliArgs,
            envVars: envVars
        )
        do {
            _ = try store.insert(config)
            return CallTool.Result(
                content: [.text(text: "Added server '\(serverKey)'", annotations: nil, _meta: nil)],
                isError: nil
            )
        } catch {
            return toolError("Failed to add server: \(error.localizedDescription)")
        }
    }

    // MARK: - remove_server

    @MainActor
    private static func removeServer(store: ConfigStore, args: [String: Value]) async -> CallTool.Result {
        guard let serverName = args["server_name"]?.stringValue, !serverName.isEmpty else {
            return toolError("Missing required argument: 'server_name'")
        }
        if serverName == "mcp-inator" {
            return toolError("'mcp-inator' is a built-in entry and cannot be removed")
        }
        guard let config = store.configs.first(where: { $0.serverKey == serverName }) else {
            return toolError("server '\(serverName)' not found")
        }
        do {
            try store.delete(config)
            return CallTool.Result(
                content: [.text(text: "Removed server '\(serverName)'", annotations: nil, _meta: nil)],
                isError: nil
            )
        } catch {
            return toolError("Failed to remove server: \(error.localizedDescription)")
        }
    }

    // MARK: - enable_server

    @MainActor
    private static func enableServer(store: ConfigStore, args: [String: Value]) async -> CallTool.Result {
        guard let serverName = args["server_name"]?.stringValue, !serverName.isEmpty else {
            return toolError("Missing required argument: 'server_name'")
        }
        guard let agentStr = args["agent"]?.stringValue, !agentStr.isEmpty else {
            return toolError("Missing required argument: 'agent'")
        }
        guard let agentType = AgentType(rawValue: agentStr) else {
            return toolError("Unknown agent '\(agentStr)'. Valid values: claude_code, claude_desktop, gemini_cli, codex_cli, gemini_desktop")
        }
        if agentType.isAppManaged {
            return toolError("agent '\(agentStr)' is app-managed and cannot be configured via mcp-inator")
        }
        guard let config = store.configs.first(where: { $0.serverKey == serverName }) else {
            return toolError("server '\(serverName)' not found")
        }
        guard let agent = store.agents.first(where: { $0.agentType == agentType }),
              let agentId = agent.id else {
            return toolError("agent '\(agentStr)' not found — run a discovery scan first")
        }

        let adapter = adapterFor(agentType)
        let configPath = URL(fileURLWithPath: agent.configPath)

        // For mcp-inator's own entry, substitute the real executable path at write time
        var effectiveConfig = config
        if config.isBuiltIn, let execPath = Bundle.main.executableURL?.path {
            effectiveConfig.command = execPath
        }

        do {
            let result = try store.enableConfig(
                uuid: effectiveConfig.uuid,
                agentId: agentId,
                adapter: adapter,
                configPath: configPath,
                force: false
            )
            switch result {
            case .success:
                return CallTool.Result(
                    content: [.text(text: "Enabled '\(serverName)' for \(agentStr)", annotations: nil, _meta: nil)],
                    isError: nil
                )
            case .driftDetected:
                return toolError("Drift detected in '\(agentStr)' config — re-run with force or resolve manually")
            }
        } catch {
            return toolError("Failed to enable server: \(error.localizedDescription)")
        }
    }

    // MARK: - disable_server

    @MainActor
    private static func disableServer(store: ConfigStore, args: [String: Value]) async -> CallTool.Result {
        guard let serverName = args["server_name"]?.stringValue, !serverName.isEmpty else {
            return toolError("Missing required argument: 'server_name'")
        }
        guard let agentStr = args["agent"]?.stringValue, !agentStr.isEmpty else {
            return toolError("Missing required argument: 'agent'")
        }
        guard let agentType = AgentType(rawValue: agentStr) else {
            return toolError("Unknown agent '\(agentStr)'. Valid values: claude_code, claude_desktop, gemini_cli, codex_cli, gemini_desktop")
        }
        if agentType.isAppManaged {
            return toolError("agent '\(agentStr)' is app-managed and cannot be configured via mcp-inator")
        }
        guard let config = store.configs.first(where: { $0.serverKey == serverName }) else {
            return toolError("server '\(serverName)' not found")
        }
        guard let agent = store.agents.first(where: { $0.agentType == agentType }),
              let agentId = agent.id else {
            return toolError("agent '\(agentStr)' not found — run a discovery scan first")
        }

        let adapter = adapterFor(agentType)
        let configPath = URL(fileURLWithPath: agent.configPath)

        do {
            let result = try store.disableConfig(
                uuid: config.uuid,
                agentId: agentId,
                adapter: adapter,
                configPath: configPath,
                force: false
            )
            switch result {
            case .success:
                return CallTool.Result(
                    content: [.text(text: "Disabled '\(serverName)' for \(agentStr)", annotations: nil, _meta: nil)],
                    isError: nil
                )
            case .driftDetected:
                return toolError("Drift detected in '\(agentStr)' config — re-run with force or resolve manually")
            }
        } catch {
            return toolError("Failed to disable server: \(error.localizedDescription)")
        }
    }

    // MARK: - list_agents

    @MainActor
    private static func listAgents(store: ConfigStore) -> CallTool.Result {
        struct AgentSummary: Encodable {
            let agentType: String
            let displayName: String
            let configPath: String
            let isAvailable: Bool
        }
        let summaries = store.agents.map { a in
            AgentSummary(
                agentType: a.agentType.rawValue,
                displayName: a.displayName,
                configPath: a.configPath,
                isAvailable: a.isAvailable
            )
        }
        guard let data = try? JSONEncoder().encode(summaries),
              let json = String(data: data, encoding: .utf8) else {
            return toolError("Failed to serialize agent list")
        }
        return CallTool.Result(content: [.text(text: json, annotations: nil, _meta: nil)], isError: nil)
    }

    // MARK: - Helpers

    private static func toolError(_ message: String) -> CallTool.Result {
        CallTool.Result(
            content: [.text(text: "Error: \(message)", annotations: nil, _meta: nil)],
            isError: true
        )
    }

    private static func adapterFor(_ agentType: AgentType) -> any AgentAdapter {
        switch agentType {
        case .claudeCode:    return ClaudeCodeAdapter()
        case .claudeDesktop: return ClaudeDesktopAdapter()
        case .geminiCLI:     return GeminiCLIAdapter()
        case .codexCLI:      return CodexCLIAdapter()
        case .geminiDesktop: return GeminiDesktopAdapter()
        }
    }
}
