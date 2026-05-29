import Foundation
@testable import mcp_inator

final class StubAdapter: AgentAdapter {
    let agentType: AgentType
    let displayName: String
    var installedResult = true
    var appManagedResult = false
    var configPathResult: URL
    var readResult: [String: MCPServerConfig] = [:]

    init(
        agentType: AgentType = .claudeDesktop,
        displayName: String = "Stub",
        configPath: URL = URL(fileURLWithPath: "/dev/null")
    ) {
        self.agentType = agentType
        self.displayName = displayName
        self.configPathResult = configPath
    }

    func defaultConfigPath() -> URL { configPathResult }
    func isInstalled() -> Bool { installedResult }
    var isAppManaged: Bool { appManagedResult }

    func readConfigs(from path: URL) throws -> [String: MCPServerConfig] { readResult }

    func writeConfigs(
        _ configs: [String: MCPServerConfig],
        to path: URL,
        expectedExisting: [String: MCPServerConfig]?
    ) throws -> WriteResult { .success }

    func removeConfig(
        key: String,
        from path: URL,
        expectedValue: MCPServerConfig?
    ) throws -> WriteResult { .success }

    func validateServerKey(_ key: String) -> KeyValidationResult { .valid }
}
