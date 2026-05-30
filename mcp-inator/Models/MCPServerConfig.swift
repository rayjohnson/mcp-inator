import Foundation
import GRDB

// MARK: - TransportType

enum TransportType: String, Codable, CaseIterable {
    case stdio
    case http
    case sse
}

struct MCPServerConfig: Identifiable {
    var id: Int64?
    var uuid: UUID
    var displayName: String
    var serverKey: String
    var transportType: TransportType
    var command: String       // stdio only
    var args: [String]        // stdio only
    var url: String           // http/sse only
    var envVars: [EnvVar]     // stdio: env vars; http/sse: request headers
    var notes: String
    var isPrivate: Bool       // excludes server from usage sharing and catalog stats
    var createdAt: Date
    var updatedAt: Date

    // stdio initializer (default)
    init(
        displayName: String,
        serverKey: String? = nil,
        command: String,
        args: [String] = [],
        envVars: [EnvVar] = [],
        notes: String = "",
        isPrivate: Bool = false
    ) {
        self.id = nil
        self.uuid = UUID()
        self.displayName = displayName
        self.serverKey = serverKey ?? MCPServerConfig.generateKey(from: displayName)
        self.transportType = .stdio
        self.command = command
        self.args = args
        self.url = ""
        self.envVars = envVars
        self.notes = notes
        self.isPrivate = isPrivate
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }

    // http/sse initializer
    init(
        displayName: String,
        serverKey: String? = nil,
        transportType: TransportType,
        url: String,
        headers: [EnvVar] = [],
        notes: String = "",
        isPrivate: Bool = false
    ) {
        self.id = nil
        self.uuid = UUID()
        self.displayName = displayName
        self.serverKey = serverKey ?? MCPServerConfig.generateKey(from: displayName)
        self.transportType = transportType
        self.command = ""
        self.args = []
        self.url = url
        self.envVars = headers
        self.notes = notes
        self.isPrivate = isPrivate
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }

    var isHTTP: Bool { transportType == .http || transportType == .sse }
    var isBuiltIn: Bool { serverKey == "mcp-inator" }
    var displayCommand: String { command.isEmpty ? serverKey : command }
}

// MARK: - RegistryEntry Convenience Init

extension MCPServerConfig {
    init(from entry: RegistryEntry) {
        if entry.transportType == .stdio {
            let derived = entry.packageType.map {
                RegistryEntry.deriveCommand(packageType: $0, identifier: entry.packageIdentifier ?? "")
            }
            let envVars = entry.envVars.map { envVarDef -> EnvVar in
                var ev = EnvVar(key: envVarDef.name, value: "", isSensitive: envVarDef.isSecret)
                ev.isHint = true
                return ev
            }
            self.init(
                displayName: entry.displayName,
                command: derived?.command ?? "",
                args: derived?.args ?? [],
                envVars: envVars
            )
        } else {
            let headers = entry.remoteHeaders.map { header -> EnvVar in
                var ev = EnvVar(key: header.name, value: header.valueTemplate ?? "", isSensitive: header.isSecret)
                ev.isHint = true
                return ev
            }
            self.init(
                displayName: entry.displayName,
                transportType: entry.transportType,
                url: entry.remoteURL ?? "",
                headers: headers
            )
        }
    }
}

// MARK: - Server Key Transform

extension MCPServerConfig {
    static func generateKey(from displayName: String) -> String {
        let lowercased = displayName.lowercased()
        let hyphenated = lowercased.replacingOccurrences(of: " ", with: "-")
        let filtered = hyphenated.unicodeScalars.filter { scalar in
            (scalar.value >= 97 && scalar.value <= 122) ||
            (scalar.value >= 48 && scalar.value <= 57) ||
            scalar.value == 45
        }
        return String(String.UnicodeScalarView(filtered))
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

// MARK: - Equatable (compares agent-file fields only for drift detection)

extension MCPServerConfig: Equatable {
    static func == (lhs: MCPServerConfig, rhs: MCPServerConfig) -> Bool {
        // envVars are compared order-independently: the JSON writer uses sortedKeys so
        // on-disk order is always alphabetical, but snapshots may store registry order.
        let lhsEnv = lhs.envVars.sorted { $0.key < $1.key }
        let rhsEnv = rhs.envVars.sorted { $0.key < $1.key }
        return lhs.transportType == rhs.transportType &&
               lhs.command == rhs.command &&
               lhs.args == rhs.args &&
               lhs.url == rhs.url &&
               lhsEnv == rhsEnv
    }
}

// MARK: - GRDB Persistence

extension MCPServerConfig: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "mcp_server_configs"

    init(row: Row) throws {
        id = row["id"]
        let uuidString: String = row["uuid"]
        uuid = UUID(uuidString: uuidString) ?? UUID()
        displayName = row["displayName"]
        serverKey = row["serverKey"]

        let transportRaw: String = row["transportType"] ?? "stdio"
        transportType = TransportType(rawValue: transportRaw) ?? .stdio

        command = row["command"] ?? ""
        url = row["url"] ?? ""

        let argsJSON: String = row["args"]
        args = (try? JSONDecoder().decode([String].self, from: Data(argsJSON.utf8))) ?? []

        let envJSON: String = row["envVars"]
        envVars = (try? JSONDecoder().decode([EnvVar].self, from: Data(envJSON.utf8))) ?? []

        notes = row["notes"] ?? ""
        isPrivate = (row["isPrivate"] as? Bool) ?? false

        let created: Double = row["createdAt"]
        createdAt = Date(timeIntervalSince1970: created)
        let updated: Double = row["updatedAt"]
        updatedAt = Date(timeIntervalSince1970: updated)
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["uuid"] = uuid.uuidString
        container["displayName"] = displayName
        container["serverKey"] = serverKey
        container["transportType"] = transportType.rawValue
        container["command"] = command
        container["url"] = url
        container["args"] = String(data: try JSONEncoder().encode(args), encoding: .utf8) ?? "[]"
        container["envVars"] = String(data: try JSONEncoder().encode(envVars), encoding: .utf8) ?? "[]"
        container["notes"] = notes
        container["isPrivate"] = isPrivate
        container["createdAt"] = createdAt.timeIntervalSince1970
        container["updatedAt"] = updatedAt.timeIntervalSince1970
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Codable (for lastWrittenSnapshot storage)

extension MCPServerConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case uuid, displayName, serverKey, transportType, command, args, url, envVars, notes, isPrivate, createdAt, updatedAt
    }
}

// MARK: - EnvVar

struct EnvVar: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var key: String
    var value: String
    var isSensitive: Bool
    var isHint: Bool = false  // Not persisted — marks registry-suggested values

    init(key: String, value: String, isSensitive: Bool? = nil) {
        self.key = key
        self.value = value
        self.isSensitive = isSensitive ?? EnvVar.defaultSensitivity(for: value)
    }

    // id is excluded from Codable (not stored in files or snapshots) so synthesized
    // == would always return false across encode/decode cycles. Compare content only.
    static func == (lhs: EnvVar, rhs: EnvVar) -> Bool {
        lhs.key == rhs.key && lhs.value == rhs.value && lhs.isSensitive == rhs.isSensitive
    }

    // FR-016: env var references like ${GITHUB_TOKEN} are not sensitive; literals are.
    static func defaultSensitivity(for value: String) -> Bool {
        let pattern = #"^\$\{[A-Z_][A-Z0-9_]*\}$"#
        return value.range(of: pattern, options: .regularExpression) == nil
    }

    enum CodingKeys: String, CodingKey { case key, value, isSensitive }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        value = try container.decode(String.self, forKey: .value)
        isSensitive = try container.decode(Bool.self, forKey: .isSensitive)
    }
}
