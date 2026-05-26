import Foundation
import GRDB

struct MCPServerConfig: Identifiable {
    var id: Int64?
    var uuid: UUID
    var displayName: String
    var serverKey: String
    var command: String
    var args: [String]
    var envVars: [EnvVar]
    var notes: String
    var createdAt: Date
    var updatedAt: Date

    init(
        displayName: String,
        serverKey: String? = nil,
        command: String,
        args: [String] = [],
        envVars: [EnvVar] = [],
        notes: String = ""
    ) {
        self.id = nil
        self.uuid = UUID()
        self.displayName = displayName
        self.serverKey = serverKey ?? MCPServerConfig.generateKey(from: displayName)
        self.command = command
        self.args = args
        self.envVars = envVars
        self.notes = notes
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }
}

// MARK: - Server Key Transform (FR-001, T022)

extension MCPServerConfig {
    static func generateKey(from displayName: String) -> String {
        let lowercased = displayName.lowercased()
        let hyphenated = lowercased.replacingOccurrences(of: " ", with: "-")
        // Keep only a-z, 0-9, hyphen
        let filtered = hyphenated.unicodeScalars.filter { s in
            (s.value >= 97 && s.value <= 122) || // a-z
            (s.value >= 48 && s.value <= 57) ||  // 0-9
            s.value == 45                         // hyphen
        }
        return String(String.UnicodeScalarView(filtered))
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

// MARK: - Equatable (for drift comparison — compares agent-file fields only)

extension MCPServerConfig: Equatable {
    static func == (lhs: MCPServerConfig, rhs: MCPServerConfig) -> Bool {
        lhs.command == rhs.command &&
        lhs.args == rhs.args &&
        lhs.envVars == rhs.envVars
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
        command = row["command"]

        let argsJSON: String = row["args"]
        args = (try? JSONDecoder().decode([String].self, from: Data(argsJSON.utf8))) ?? []

        let envJSON: String = row["envVars"]
        envVars = (try? JSONDecoder().decode([EnvVar].self, from: Data(envJSON.utf8))) ?? []

        notes = row["notes"] ?? ""

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
        container["command"] = command
        container["args"] = String(data: try JSONEncoder().encode(args), encoding: .utf8) ?? "[]"
        container["envVars"] = String(data: try JSONEncoder().encode(envVars), encoding: .utf8) ?? "[]"
        container["notes"] = notes
        container["createdAt"] = createdAt.timeIntervalSince1970
        container["updatedAt"] = updatedAt.timeIntervalSince1970
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Codable (for lastWrittenSnapshot JSON storage in ConfigAgentAssignment)

extension MCPServerConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case uuid, displayName, serverKey, command, args, envVars, notes, createdAt, updatedAt
    }
}

// MARK: - EnvVar

struct EnvVar: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var key: String
    var value: String
    var isSensitive: Bool

    init(key: String, value: String, isSensitive: Bool? = nil) {
        self.key = key
        self.value = value
        self.isSensitive = isSensitive ?? EnvVar.defaultSensitivity(for: value)
    }

    // FR-016: env var references like ${GITHUB_TOKEN} are not sensitive; literals are.
    static func defaultSensitivity(for value: String) -> Bool {
        let pattern = #"^\$\{[A-Z_][A-Z0-9_]*\}$"#
        return value.range(of: pattern, options: .regularExpression) == nil
    }

    // Coding: exclude auto-generated id from persistence
    enum CodingKeys: String, CodingKey { case key, value, isSensitive }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        value = try c.decode(String.self, forKey: .value)
        isSensitive = try c.decode(Bool.self, forKey: .isSensitive)
    }
}
