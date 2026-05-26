import Foundation
import AppKit

struct GeminiDesktopAdapter: AgentAdapter {

    let agentType: AgentType = .geminiDesktop
    let displayName: String = "Gemini Desktop"

    // MCP config is managed internally by Gemini Desktop's SQLite database.
    var isAppManaged: Bool { true }

    func defaultConfigPath() -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/Google/Gemini/mcp_servers.json")
    }

    func isInstalled() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.GeminiMacOS") != nil
            || FileManager.default.fileExists(atPath: "/Applications/Gemini.app")
    }

    // No-ops — Gemini Desktop manages MCP config internally.

    func readConfigs(from path: URL) throws -> [String: MCPServerConfig] {
        return [:]
    }

    func writeConfigs(
        _ configs: [String: MCPServerConfig],
        to path: URL,
        expectedExisting: [String: MCPServerConfig]?
    ) throws -> WriteResult {
        return .success
    }

    func removeConfig(key: String, from path: URL, expectedValue: MCPServerConfig?) throws -> WriteResult {
        return .success
    }

    func validateServerKey(_ key: String) -> KeyValidationResult {
        return .valid
    }
}
