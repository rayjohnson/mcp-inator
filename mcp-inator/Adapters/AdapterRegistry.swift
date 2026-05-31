import Foundation

// MARK: - AdapterRegistry
//
// To add a new agent: add an AgentDefinition below and add it to both
// `definitions` and `all`. No other files need to change.

enum AdapterRegistry {

    // MARK: - Definitions (icon config and metadata for all agents)

    static let definitions: [AgentDefinition] = [
        claudeCodeDef, claudeDesktopDef, geminiCLIDef, codexCLIDef, geminiDesktopDef, cursorDef
    ]

    // MARK: - Adapters (read/write implementations)

    nonisolated(unsafe) static let all: [any AgentAdapter] = [
        ClaudeCodeAdapter(),
        FileBasedAdapter(definition: claudeDesktopDef),
        FileBasedAdapter(definition: geminiCLIDef),
        CodexCLIAdapter(),
        FileBasedAdapter(definition: geminiDesktopDef),
        FileBasedAdapter(definition: cursorDef)
    ]

    static func adapter(for agentType: AgentType) -> (any AgentAdapter)? {
        all.first { $0.agentType == agentType }
    }

    static func definition(for agentType: AgentType) -> AgentDefinition? {
        definitions.first { $0.agentType == agentType }
    }

    // MARK: - Agent Definitions

    static let claudeCodeDef = AgentDefinition(
        agentType: .claudeCode,
        displayName: "Claude Code",
        configPathRelative: ".claude.json",
        mcpKey: "mcpServers",
        icon: AgentIconConfig(
            bundleIds: ["com.anthropic.claudefordesktop", "com.anthropic.claude"],
            appPaths: [],
            fallback: .init(letter: "A", red: 0.85, green: 0.45, blue: 0.25)
        ),
        keyValidation: KeyValidationConfig(
            pattern: "^[a-z0-9][a-z0-9-]*$",
            errorMessage: "Server key must start with a letter or digit and contain only a-z, 0-9, or hyphens.",
            reservedWords: ["workspace"]
        )
    )

    static let claudeDesktopDef = AgentDefinition(
        agentType: .claudeDesktop,
        displayName: "Claude Desktop",
        configPathRelative: "Library/Application Support/Claude/claude_desktop_config.json",
        mcpKey: "mcpServers",
        icon: AgentIconConfig(
            bundleIds: ["com.anthropic.claudefordesktop", "com.anthropic.claude"],
            appPaths: [],
            fallback: .init(letter: "A", red: 0.85, green: 0.45, blue: 0.25)
        ),
        keyValidation: KeyValidationConfig(
            pattern: "^[a-z0-9][a-z0-9-]*$",
            errorMessage: "Server key must start with a letter or digit and contain only a-z, 0-9, or hyphens."
        )
    )

    static let geminiCLIDef = AgentDefinition(
        agentType: .geminiCLI,
        displayName: "Gemini CLI",
        configPathRelative: ".gemini/settings.json",
        mcpKey: "mcpServers",
        icon: AgentIconConfig(
            bundleIds: [],
            appPaths: [],
            fallback: .init(letter: "G", red: 0.26, green: 0.52, blue: 0.96)
        ),
        keyValidation: KeyValidationConfig(
            pattern: "^[a-z0-9][a-z0-9-]*$",
            errorMessage: "Server key must start with a letter or digit and contain only a-z, 0-9, or hyphens.",
            rejectUnderscores: true
        )
    )

    static let codexCLIDef = AgentDefinition(
        agentType: .codexCLI,
        displayName: "Codex CLI",
        configPathRelative: ".codex/config.toml",
        mcpKey: "mcp_servers",
        icon: AgentIconConfig(
            bundleIds: [],
            appPaths: [],
            fallback: .init(letter: "X", red: 0.07, green: 0.07, blue: 0.07)
        ),
        keyValidation: KeyValidationConfig(
            pattern: "^[a-z0-9][a-z0-9_-]*$",
            errorMessage: "Server key must start with a letter or digit and contain only a-z, 0-9, hyphens, or underscores."
        )
    )

    static let geminiDesktopDef = AgentDefinition(
        agentType: .geminiDesktop,
        displayName: "Gemini Desktop",
        configPathRelative: "Library/Application Support/Google/Gemini/mcp_servers.json",
        mcpKey: "mcpServers",
        icon: AgentIconConfig(
            bundleIds: ["com.google.GeminiMacOS"],
            appPaths: ["/Applications/Gemini.app"],
            fallback: .init(letter: "G", red: 0.11, green: 0.53, blue: 0.96)
        ),
        keyValidation: KeyValidationConfig(
            pattern: "^[a-z0-9][a-z0-9-]*$",
            errorMessage: "Server key must start with a letter or digit and contain only a-z, 0-9, or hyphens."
        ),
        isAppManaged: true
    )

    static let cursorDef = AgentDefinition(
        agentType: .cursor,
        displayName: "Cursor",
        configPathRelative: ".cursor/mcp.json",
        mcpKey: "mcpServers",
        icon: AgentIconConfig(
            bundleIds: ["com.todesktop.230313mzl4w4u92"],
            appPaths: ["/Applications/Cursor.app"],
            fallback: .init(letter: "C", red: 0.07, green: 0.07, blue: 0.07)
        ),
        keyValidation: KeyValidationConfig(
            pattern: "^[a-z0-9][a-z0-9-]*$",
            errorMessage: "Server key must start with a letter or digit and contain only a-z, 0-9, or hyphens."
        )
    )
}
