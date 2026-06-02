import Foundation

struct ZedAdapter: AgentAdapter {

    let agentType: AgentType = .zed
    let displayName: String = "Zed"
    let homeDirectory: URL
    let appBundlePath: String

    init(
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()),
        appBundlePath: String = "/Applications/Zed.app"
    ) {
        self.homeDirectory = homeDirectory
        self.appBundlePath = appBundlePath
    }

    func defaultConfigPath() -> URL {
        homeDirectory.appendingPathComponent(".config/zed/settings.json")
    }

    func isInstalled() -> Bool {
        let configFile = defaultConfigPath()
        let zedDir = homeDirectory.appendingPathComponent(".config/zed")
        return FileManager.default.fileExists(atPath: configFile.path) ||
               FileManager.default.fileExists(atPath: zedDir.path) ||
               FileManager.default.fileExists(atPath: appBundlePath)
    }

    func readConfigs(from path: URL) throws -> [String: MCPServerConfig] {
        let json = try JSONAdapterHelper.readFullJSON(from: path)
        let serverDict = json["context_servers"] as? [String: Any] ?? [:]
        return Self.parseZedConfigs(from: serverDict)
    }

    func writeConfigs(
        _ configs: [String: MCPServerConfig],
        to path: URL,
        expectedExisting: [String: MCPServerConfig]?
    ) throws -> WriteResult {
        var json = try JSONAdapterHelper.readFullJSON(from: path)
        let existingServerDict = json["context_servers"] as? [String: Any] ?? [:]
        let onDiskParsed = Self.parseZedConfigs(from: existingServerDict)

        if let expected = expectedExisting,
           JSONAdapterHelper.checkDrift(onDisk: onDiskParsed, expected: expected) {
            return .driftDetected(onDisk: onDiskParsed, expected: expected)
        }

        var serverDict = existingServerDict
        for (key, config) in configs {
            serverDict[key] = Self.serializeZedConfig(config)
        }
        json["context_servers"] = serverDict
        try JSONAdapterHelper.writeAtomic(json: json, to: path)
        return .success
    }

    func removeConfig(key: String, from path: URL, expectedValue: MCPServerConfig?) throws -> WriteResult {
        var json = try JSONAdapterHelper.readFullJSON(from: path)
        var serverDict = json["context_servers"] as? [String: Any] ?? [:]
        let onDiskParsed = Self.parseZedConfigs(from: serverDict)

        if let expected = expectedValue {
            if JSONAdapterHelper.checkDrift(onDisk: onDiskParsed, expected: [key: expected]) {
                return .driftDetected(onDisk: onDiskParsed, expected: [key: expected])
            }
        }

        serverDict.removeValue(forKey: key)
        json["context_servers"] = serverDict
        try JSONAdapterHelper.writeAtomic(json: json, to: path)
        return .success
    }

    func validateServerKey(_ key: String) -> KeyValidationResult {
        if !key.matches(pattern: "^[a-z0-9][a-z0-9-]*$") {
            return .invalid(reason: "Server key must start with a letter or digit and contain only a-z, 0-9, or hyphens.")
        }
        return .valid
    }

    // MARK: - Zed-format entry parsing

    private static func parseZedConfigs(from serverDict: [String: Any]) -> [String: MCPServerConfig] {
        var result: [String: MCPServerConfig] = [:]
        for (key, value) in serverDict {
            guard let entry = value as? [String: Any],
                  let commandObj = entry["command"] as? [String: Any],
                  let path = commandObj["path"] as? String else { continue }
            let args = commandObj["args"] as? [String] ?? []
            let env = entry["env"] as? [String: String] ?? [:]
            let envVars = env.sorted(by: { $0.key < $1.key })
                .map { EnvVar(key: $0.key, value: $0.value) }
            result[key] = MCPServerConfig(
                displayName: key, serverKey: key,
                command: path, args: args, envVars: envVars
            )
        }
        return result
    }

    private static func serializeZedConfig(_ config: MCPServerConfig) -> [String: Any] {
        var commandObj: [String: Any] = ["path": config.command]
        if !config.args.isEmpty { commandObj["args"] = config.args }
        var entry: [String: Any] = ["command": commandObj]
        if !config.envVars.isEmpty {
            entry["env"] = Dictionary(uniqueKeysWithValues: config.envVars.map { ($0.key, $0.value) })
        }
        return entry
    }
}
