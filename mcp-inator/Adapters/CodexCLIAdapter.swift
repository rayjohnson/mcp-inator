import Foundation
import TOMLKit

// Codex CLI uses TOML (not JSON). Manages the [mcp_servers] section.
// All other TOML keys in ~/.codex/config.toml are preserved on read-write.
struct CodexCLIAdapter: AgentAdapter {

    let agentType: AgentType = .codexCLI
    let displayName: String = "Codex CLI"
    private let sectionKey = "mcp_servers"

    func defaultConfigPath() -> URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/config.toml")
    }

    func isInstalled() -> Bool {
        let path = defaultConfigPath()
        return FileManager.default.fileExists(atPath: path.path) ||
               FileManager.default.fileExists(atPath: path.deletingLastPathComponent().path)
    }

    // MARK: - Read

    func readConfigs(from path: URL) throws -> [String: MCPServerConfig] {
        guard FileManager.default.fileExists(atPath: path.path) else { return [:] }
        let raw: String
        do {
            raw = try String(contentsOf: path, encoding: .utf8)
        } catch {
            throw AdapterError.parseFailure(path, underlying: error)
        }
        let toml: TOMLTable
        do {
            toml = try TOMLTable(string: raw)
        } catch {
            throw AdapterError.parseFailure(path, underlying: error)
        }
        guard let servers = toml[sectionKey]?.table else { return [:] }
        return parseConfigs(from: servers)
    }

    private func parseConfigs(from table: TOMLTable) -> [String: MCPServerConfig] {
        var result: [String: MCPServerConfig] = [:]
        for (key, value) in table {
            guard let entry = value.table,
                  let command = entry["command"]?.string else { continue }
            let args: [String] = {
                guard let arr = entry["args"]?.array else { return [] }
                return arr.compactMap { $0.string }
            }()
            let envVars: [EnvVar] = {
                guard let envTable = entry["env"]?.table else { return [] }
                return envTable.keys.sorted().compactMap { k in
                    guard let str = envTable[k]?.string else { return nil }
                    return EnvVar(key: k, value: str)
                }
            }()
            result[key] = MCPServerConfig(
                displayName: key, serverKey: key,
                command: command, args: args, envVars: envVars
            )
        }
        return result
    }

    // MARK: - Write

    func writeConfigs(
        _ configs: [String: MCPServerConfig],
        to path: URL,
        expectedExisting: [String: MCPServerConfig]?
    ) throws -> WriteResult {
        let toml = try readFullTOML(from: path)
        let onDiskParsed: [String: MCPServerConfig]
        if let existing = toml[sectionKey]?.table {
            onDiskParsed = parseConfigs(from: existing)
        } else {
            onDiskParsed = [:]
        }

        if let expected = expectedExisting,
           JSONAdapterHelper.checkDrift(onDisk: onDiskParsed, expected: expected) {
            return .driftDetected(onDisk: onDiskParsed, expected: expected)
        }

        let serversTable: TOMLTable = toml[sectionKey]?.table ?? TOMLTable()
        for (key, config) in configs {
            serversTable[key] = serializeConfig(config)
        }
        toml[sectionKey] = serversTable
        try writeAtomic(toml: toml, to: path)
        return .success
    }

    func removeConfig(key: String, from path: URL, expectedValue: MCPServerConfig?) throws -> WriteResult {
        let toml = try readFullTOML(from: path)
        guard let servers = toml[sectionKey]?.table else { return .success }
        let onDiskParsed = parseConfigs(from: servers)

        if let expected = expectedValue,
           JSONAdapterHelper.checkDrift(onDisk: onDiskParsed, expected: [key: expected]) {
            return .driftDetected(onDisk: onDiskParsed, expected: [key: expected])
        }

        servers.remove(at: key)
        try writeAtomic(toml: toml, to: path)
        return .success
    }

    // MARK: - Validation

    func validateServerKey(_ key: String) -> KeyValidationResult {
        if !key.matches(pattern: "^[a-z0-9][a-z0-9_-]*$") {
            return .invalid(reason: "Server key must start with a letter or digit and contain only a-z, 0-9, hyphens, or underscores.")
        }
        return .valid
    }

    // MARK: - Private Helpers

    private func readFullTOML(from path: URL) throws -> TOMLTable {
        guard FileManager.default.fileExists(atPath: path.path) else {
            return TOMLTable()
        }
        do {
            let raw = try String(contentsOf: path, encoding: .utf8)
            return try TOMLTable(string: raw)
        } catch {
            throw AdapterError.parseFailure(path, underlying: error)
        }
    }

    private func serializeConfig(_ config: MCPServerConfig) -> TOMLTable {
        let table = TOMLTable()
        table["command"] = config.command
        if !config.args.isEmpty {
            table["args"] = TOMLArray(config.args)
        }
        if !config.envVars.isEmpty {
            let envTable = TOMLTable()
            for ev in config.envVars { envTable[ev.key] = ev.value }
            table["env"] = envTable
        }
        return table
    }

    private func writeAtomic(toml: TOMLTable, to url: URL) throws {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let output = toml.convert()
            let tempURL = url.deletingLastPathComponent()
                .appendingPathComponent(UUID().uuidString + ".tmp")
            try output.write(to: tempURL, atomically: false, encoding: .utf8)
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
}
