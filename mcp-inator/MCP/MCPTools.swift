import Foundation
import MCP

// MARK: - MCPToolHandler

struct MCPToolHandler: @unchecked Sendable {
    let store: ConfigStore
    let catalogStore: CatalogStore
    var adapterProvider: (AgentType) -> any AgentAdapter

    init(store: ConfigStore, catalogStore: CatalogStore, adapterProvider: ((AgentType) -> any AgentAdapter)? = nil) {
        self.store = store
        self.catalogStore = catalogStore
        self.adapterProvider = adapterProvider ?? MCPToolHandler.defaultAdapter
    }

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
            ),
            Tool(
                name: "list_catalog",
                description: "List available MCP servers from the built-in catalog, including their command, args, and required environment variables.",
                inputSchema: .object(["type": "object", "properties": .object([:]), "required": .array([])])
            )
        ]
    }

    // MARK: - Dispatch

    @MainActor
    func dispatch(params: CallTool.Parameters) async -> CallTool.Result {
        let args = params.arguments ?? [:]
        switch params.name {
        case "list_servers":   return listServers()
        case "add_server":     return await addServer(args: args)
        case "remove_server":  return await removeServer(args: args)
        case "enable_server":  return await enableServer(args: args)
        case "disable_server": return await disableServer(args: args)
        case "list_agents":    return listAgents()
        case "list_catalog":   return listCatalog()
        default:
            return toolError("Unknown tool: '\(params.name)'")
        }
    }

    // MARK: - list_servers

    @MainActor
    private func listServers() -> CallTool.Result {
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
    private func addServer(args: [String: Value]) async -> CallTool.Result {
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
    private func removeServer(args: [String: Value]) async -> CallTool.Result {
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
    private func enableServer(args: [String: Value]) async -> CallTool.Result {
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

        let adapter = adapterProvider(agentType)
        let configPath = URL(fileURLWithPath: agent.configPath)

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
    private func disableServer(args: [String: Value]) async -> CallTool.Result {
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

        let adapter = adapterProvider(agentType)
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
    private func listAgents() -> CallTool.Result {
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

    // MARK: - list_catalog

    @MainActor
    private func listCatalog() -> CallTool.Result {
        struct EnvVarSummary: Encodable {
            let name: String
            let description: String
            let isRequired: Bool
            let isSensitive: Bool
            let defaultValue: String?
        }
        struct CatalogSummary: Encodable {
            let serverKey: String
            let displayName: String
            let category: String
            let shortDescription: String
            let transportType: String
            let command: String
            let args: [String]
            let envVars: [EnvVarSummary]
            let isVerified: Bool
        }
        let summaries = catalogStore.entries.map { entry in
            CatalogSummary(
                serverKey: entry.serverKey,
                displayName: entry.displayName,
                category: entry.category.rawValue,
                shortDescription: entry.shortDescription,
                transportType: entry.transportType.rawValue,
                command: entry.command,
                args: entry.args,
                envVars: entry.envVars.map { envVar in
                    EnvVarSummary(
                        name: envVar.name,
                        description: envVar.description,
                        isRequired: envVar.isRequired,
                        isSensitive: envVar.isSensitive,
                        defaultValue: envVar.defaultValue
                    )
                },
                isVerified: entry.isVerified
            )
        }
        guard let data = try? JSONEncoder().encode(summaries),
              let json = String(data: data, encoding: .utf8) else {
            return toolError("Failed to serialize catalog")
        }
        return CallTool.Result(content: [.text(text: json, annotations: nil, _meta: nil)], isError: nil)
    }

    // MARK: - Helpers

    private func toolError(_ message: String) -> CallTool.Result {
        CallTool.Result(
            content: [.text(text: "Error: \(message)", annotations: nil, _meta: nil)],
            isError: true
        )
    }

    private static func defaultAdapter(_ agentType: AgentType) -> any AgentAdapter {
        switch agentType {
        case .claudeCode:    return ClaudeCodeAdapter()
        case .claudeDesktop: return ClaudeDesktopAdapter()
        case .geminiCLI:     return GeminiCLIAdapter()
        case .codexCLI:      return CodexCLIAdapter()
        case .geminiDesktop: return GeminiDesktopAdapter()
        }
    }
}
