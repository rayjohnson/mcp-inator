import Foundation
import GRDB

// MARK: - AgentType

enum AgentType: String, Codable, CaseIterable {
    case claudeCode    = "claude_code"
    case claudeDesktop = "claude_desktop"
    case geminiCLI     = "gemini_cli"
    case codexCLI      = "codex_cli"
    case geminiDesktop = "gemini_desktop"

    var displayName: String {
        switch self {
        case .claudeCode:    return "Claude Code"
        case .claudeDesktop: return "Claude Desktop"
        case .geminiCLI:     return "Gemini CLI"
        case .codexCLI:      return "Codex CLI"
        case .geminiDesktop: return "Gemini Desktop"
        }
    }

    var isAppManaged: Bool {
        switch self {
        case .geminiDesktop: return true
        default: return false
        }
    }

    var defaultConfigPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        switch self {
        case .claudeCode:
            return "\(home)/.claude.json"
        case .claudeDesktop:
            return "\(home)/Library/Application Support/Claude/claude_desktop_config.json"
        case .geminiCLI:
            return "\(home)/.gemini/settings.json"
        case .codexCLI:
            return "\(home)/.codex/config.toml"
        case .geminiDesktop:
            return "\(home)/Library/Application Support/Google/Gemini/mcp_servers.json"
        }
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
        agentType = AgentType(rawValue: typeRaw) ?? .claudeCode
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
