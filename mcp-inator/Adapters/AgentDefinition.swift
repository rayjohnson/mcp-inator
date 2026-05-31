import Foundation

// MARK: - AgentIconConfig

struct AgentIconConfig {
    struct FallbackStyle {
        let letter: String
        let red: Double
        let green: Double
        let blue: Double
    }
    let bundleIds: [String]
    let appPaths: [String]
    let fallback: FallbackStyle
}

// MARK: - KeyValidationConfig

struct KeyValidationConfig {
    let pattern: String
    let errorMessage: String
    var rejectUnderscores: Bool = false
    var reservedWords: [String] = []
}

// MARK: - AgentDefinition

struct AgentDefinition {
    let agentType: AgentType
    let displayName: String
    let configPathRelative: String  // relative to home dir, e.g. ".cursor/mcp.json"
    let mcpKey: String
    let icon: AgentIconConfig
    let keyValidation: KeyValidationConfig
    var isAppManaged: Bool = false
}
