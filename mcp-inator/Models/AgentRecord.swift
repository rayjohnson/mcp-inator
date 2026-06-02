import Foundation
import GRDB

// MARK: - AgentType

// Value-type agent identifier. Static constants are provided for known agents,
// but any rawValue string is valid — no exhaustive switch required.
struct AgentType: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let claudeCode    = AgentType(rawValue: "claude_code")
    static let claudeDesktop = AgentType(rawValue: "claude_desktop")
    static let geminiCLI     = AgentType(rawValue: "gemini_cli")
    static let codexCLI      = AgentType(rawValue: "codex_cli")
    static let geminiDesktop = AgentType(rawValue: "gemini_desktop")
    static let cursor        = AgentType(rawValue: "cursor")
    static let zed           = AgentType(rawValue: "zed")

    var displayName: String {
        AdapterRegistry.adapter(for: self)?.displayName ?? rawValue
    }

    var isAppManaged: Bool {
        AdapterRegistry.adapter(for: self)?.isAppManaged ?? false
    }

    var defaultConfigPath: String {
        AdapterRegistry.adapter(for: self)?.defaultConfigPath().path
            ?? FileManager.default.homeDirectoryForCurrentUser.path
    }
}

extension AgentType: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - AgentRecord

struct AgentRecord: Identifiable {
    var id: Int64?
    let agentType: AgentType
    var displayName: String
    var configPath: String
    var isCustomPath: Bool
    var isAvailable: Bool
    var isVisible: Bool
    let discoveredAt: Date
    var lastSeenAt: Date

    init(agentType: AgentType, configPath: String? = nil) {
        self.id = nil
        self.agentType = agentType
        self.displayName = agentType.displayName
        self.configPath = configPath ?? agentType.defaultConfigPath
        self.isCustomPath = configPath != nil
        self.isAvailable = false
        self.isVisible = true
        let now = Date()
        self.discoveredAt = now
        self.lastSeenAt = now
    }
}

// MARK: - GRDB Persistence

extension AgentRecord: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "agents"

    init(row: Row) throws {
        id = row["id"]
        let typeRaw: String = row["agentType"]
        agentType = AgentType(rawValue: typeRaw)
        displayName = row["displayName"]
        configPath = row["configPath"]
        isCustomPath = (row["isCustomPath"] as Int) != 0
        isAvailable = (row["isAvailable"] as Int) != 0
        isVisible = (row["isVisible"] as Int? ?? 1) != 0

        let disc: Double = row["discoveredAt"]
        discoveredAt = Date(timeIntervalSince1970: disc)
        let seen: Double = row["lastSeenAt"]
        lastSeenAt = Date(timeIntervalSince1970: seen)
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["agentType"] = agentType.rawValue
        container["displayName"] = displayName
        container["configPath"] = configPath
        container["isCustomPath"] = isCustomPath ? 1 : 0
        container["isAvailable"] = isAvailable ? 1 : 0
        container["isVisible"] = isVisible ? 1 : 0
        container["discoveredAt"] = discoveredAt.timeIntervalSince1970
        container["lastSeenAt"] = lastSeenAt.timeIntervalSince1970
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - AssignmentState

enum AssignmentState: String, Codable {
    case enabled
    case disabled
}

// MARK: - EffectiveState (computed, not stored)

enum EffectiveState: Equatable {
    case enabled
    case disabled
    case unavailable(reason: String)
}
