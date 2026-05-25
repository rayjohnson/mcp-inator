import Foundation

// MARK: - AgentAdapter Protocol
// Per contracts/AgentAdapter.md — all format/path logic lives here; core store never touches files.

protocol AgentAdapter {

    // MARK: Identity

    var agentType: AgentType { get }
    var displayName: String { get }

    // MARK: Path Resolution

    func defaultConfigPath() -> URL

    // MARK: Discovery

    /// Returns true if the agent appears installed (config file or parent dir exists).
    /// Must NOT throw.
    func isInstalled() -> Bool

    // MARK: Reading

    /// Reads all MCP server entries from the config file at `path`.
    /// Returns empty dict if file does not exist. Throws on parse failure.
    func readConfigs(from path: URL) throws -> [String: MCPServerConfig]

    // MARK: Writing

    /// Atomically writes the full enabled-config set to the file at `path`.
    /// Pre-flight: compares keys in `expectedExisting` against on-disk values only.
    /// Unmanaged on-disk keys are ignored in the comparison.
    func writeConfigs(
        _ configs: [String: MCPServerConfig],
        to path: URL,
        expectedExisting: [String: MCPServerConfig]?
    ) throws -> WriteResult

    /// Removes a single entry by server key. Pre-flight checks `expectedValue` if provided.
    func removeConfig(
        key: String,
        from path: URL,
        expectedValue: MCPServerConfig?
    ) throws -> WriteResult

    // MARK: Validation

    func validateServerKey(_ key: String) -> KeyValidationResult
}

// MARK: - Supporting Types

enum WriteResult {
    case success
    case driftDetected(onDisk: [String: MCPServerConfig], expected: [String: MCPServerConfig])
}

enum KeyValidationResult {
    case valid
    case invalid(reason: String)
}

enum AdapterError: LocalizedError {
    case parseFailure(URL, underlying: Error)
    case writeFailure(URL, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .parseFailure(let url, let err):
            return "Could not parse config file at \(url.path): \(err.localizedDescription)"
        case .writeFailure(let url, let err):
            return "Could not write config file at \(url.path): \(err.localizedDescription)"
        }
    }
}

// MARK: - Shared JSON Helper (used by Claude Code, Claude Desktop, Gemini adapters)

enum JSONAdapterHelper {

    // MARK: Read

    static func readFullJSON(from url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        do {
            let data = try Data(contentsOf: url)
            return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        } catch {
            throw AdapterError.parseFailure(url, underlying: error)
        }
    }

    static func parseMCPConfigs(from serverDict: [String: Any]) -> [String: MCPServerConfig] {
        var result: [String: MCPServerConfig] = [:]
        for (key, value) in serverDict {
            guard let entry = value as? [String: Any],
                  let command = entry["command"] as? String else { continue }
            let args = entry["args"] as? [String] ?? []
            let env = entry["env"] as? [String: String] ?? [:]
            let envVars = env.sorted(by: { $0.key < $1.key }).map {
                EnvVar(key: $0.key, value: $0.value)
            }
            result[key] = MCPServerConfig(
                displayName: key, serverKey: key,
                command: command, args: args, envVars: envVars
            )
        }
        return result
    }

    static func serializeConfig(_ config: MCPServerConfig) -> [String: Any] {
        var result: [String: Any] = ["command": config.command]
        if !config.args.isEmpty { result["args"] = config.args }
        if !config.envVars.isEmpty {
            result["env"] = Dictionary(uniqueKeysWithValues: config.envVars.map { ($0.key, $0.value) })
        }
        return result
    }

    // MARK: Pre-flight Diff

    /// Compares only keys present in `expected` against on-disk values.
    /// Keys in the file not in `expected` are ignored (unmanaged entries).
    static func checkDrift(
        onDisk: [String: MCPServerConfig],
        expected: [String: MCPServerConfig]
    ) -> Bool {
        for (key, expectedConfig) in expected {
            guard let onDiskConfig = onDisk[key] else { return true }
            if onDiskConfig != expectedConfig { return true }
        }
        return false
    }

    // MARK: Atomic Write

    static func writeAtomic(json: [String: Any], to url: URL) throws {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONSerialization.data(
                withJSONObject: json,
                options: [.prettyPrinted, .sortedKeys]
            )
            let tempURL = url.deletingLastPathComponent()
                .appendingPathComponent(UUID().uuidString + ".tmp")
            try data.write(to: tempURL)
            _ = try FileManager.default.replaceItem(
                at: url, withItemAt: tempURL,
                backupItemName: nil, resultingItemURL: nil
            )
        } catch let error as AdapterError {
            throw error
        } catch {
            throw AdapterError.writeFailure(url, underlying: error)
        }
    }

    // MARK: Shared writeConfigs + removeConfig implementation

    static func writeConfigs(
        _ configs: [String: MCPServerConfig],
        to path: URL,
        expectedExisting: [String: MCPServerConfig]?,
        mcpKey: String
    ) throws -> WriteResult {
        var json = try readFullJSON(from: path)
        let existingServerDict = json[mcpKey] as? [String: Any] ?? [:]
        let onDiskParsed = parseMCPConfigs(from: existingServerDict)

        if let expected = expectedExisting, checkDrift(onDisk: onDiskParsed, expected: expected) {
            return .driftDetected(onDisk: onDiskParsed, expected: expected)
        }

        var serverDict = existingServerDict
        for (key, config) in configs {
            serverDict[key] = serializeConfig(config)
        }
        json[mcpKey] = serverDict
        try writeAtomic(json: json, to: path)
        return .success
    }

    static func removeConfig(
        key: String,
        from path: URL,
        expectedValue: MCPServerConfig?,
        mcpKey: String
    ) throws -> WriteResult {
        var json = try readFullJSON(from: path)
        var serverDict = json[mcpKey] as? [String: Any] ?? [:]
        let onDiskParsed = parseMCPConfigs(from: serverDict)

        if let expected = expectedValue {
            let singleExpected = [key: expected]
            if checkDrift(onDisk: onDiskParsed, expected: singleExpected) {
                return .driftDetected(onDisk: onDiskParsed, expected: singleExpected)
            }
        }

        serverDict.removeValue(forKey: key)
        json[mcpKey] = serverDict
        try writeAtomic(json: json, to: path)
        return .success
    }
}
