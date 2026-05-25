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
            let args: [String] = (entry["args"]?.array?.value as? [TOMLValue])?.compactMap(\.string) ?? []
            let envVars: [EnvVar] = {
                guard let envTable = entry["env"]?.table else { return [] }
                return envTable.sorted(by: { $0.key < $1.key }).compactMap { k, v in
                    guard let str = v.string else { return nil }
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
        var toml = try readFullTOML(from: path)
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

        var serversTable = toml[sectionKey]?.table ?? TOMLTable()
        for (key, config) in configs {
            serversTable[key] = .table(serializeConfig(config))
        }
        toml[sectionKey] = .table(serversTable)
        try writeAtomic(toml: toml, to: path)
        return .success
    }

    func removeConfig(key: String, from path: URL, expectedValue: MCPServerConfig?) throws -> WriteResult {
        var toml = try readFullTOML(from: path)
        guard var servers = toml[sectionKey]?.table else { return .success }
        let onDiskParsed = parseConfigs(from: servers)

        if let expected = expectedValue {
            if JSONAdapterHelper.checkDrift(onDisk: onDiskParsed, expected: [key: expected]) {
                return .driftDetected(onDisk: onDiskParsed, expected: [key: expected])
            }
        }

        servers.remove(key)
        toml[sectionKey] = .table(servers)
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
        var table = TOMLTable()
        table["command"] = .string(config.command)
        if !config.args.isEmpty {
            table["args"] = .array(TOMLArray(config.args.map { .string($0) }))
        }
        if !config.envVars.isEmpty {
            var envTable = TOMLTable()
            for ev in config.envVars { envTable[ev.key] = .string(ev.value) }
            table["env"] = .table(envTable)
        }
        return table
    }

    private func writeAtomic(toml: TOMLTable, to url: URL) throws {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let output = toml.debugDescription  // TOMLKit serialization
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

// MARK: - TOMLKit helpers

private extension TOMLValue {
    var table: TOMLTable? {
        if case .table(let t) = self { return t }
        return nil
    }
    var string: String? {
        if case .string(let s) = self { return s }
        return nil
    }
    var array: TOMLArray? {
        if case .array(let a) = self { return a }
        return nil
    }
}

private extension TOMLArray {
    var value: [TOMLValue] { (0..<count).map { self[$0] } }
}
