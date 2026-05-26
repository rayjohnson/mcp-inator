import Foundation
import GRDB

struct ConfigAgentAssignment: Identifiable {
    var id: Int64?
    let configUUID: UUID
    let agentId: Int64
    var state: AssignmentState
    // Last values successfully written to the agent file.
    // Used as expectedExisting in pre-flight diff checks (FR-023).
    // nil = config has never been written to this agent.
    var lastWrittenSnapshot: MCPServerConfig?
    var assignedAt: Date
    var updatedAt: Date

    init(configUUID: UUID, agentId: Int64, state: AssignmentState = .disabled) {
        self.id = nil
        self.configUUID = configUUID
        self.agentId = agentId
        self.state = state
        self.lastWrittenSnapshot = nil
        let now = Date()
        self.assignedAt = now
        self.updatedAt = now
    }
}

// MARK: - GRDB Persistence

extension ConfigAgentAssignment: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "config_agent_assignments"

    init(row: Row) throws {
        id = row["id"]
        let uuidString: String = row["configUUID"]
        configUUID = UUID(uuidString: uuidString) ?? UUID()
        agentId = row["agentId"]
        let stateRaw: String = row["state"]
        state = AssignmentState(rawValue: stateRaw) ?? .disabled

        if let snapshotJSON: String = row["lastWrittenSnapshot"],
           let data = snapshotJSON.data(using: .utf8) {
            lastWrittenSnapshot = try? JSONDecoder().decode(MCPServerConfig.self, from: data)
        } else {
            lastWrittenSnapshot = nil
        }

        let assigned: Double = row["assignedAt"]
        assignedAt = Date(timeIntervalSince1970: assigned)
        let updated: Double = row["updatedAt"]
        updatedAt = Date(timeIntervalSince1970: updated)
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["configUUID"] = configUUID.uuidString
        container["agentId"] = agentId
        container["state"] = state.rawValue

        if let snapshot = lastWrittenSnapshot,
           let data = try? JSONEncoder().encode(snapshot),
           let json = String(data: data, encoding: .utf8) {
            container["lastWrittenSnapshot"] = json
        } else {
            container["lastWrittenSnapshot"] = nil
        }

        container["assignedAt"] = assignedAt.timeIntervalSince1970
        container["updatedAt"] = updatedAt.timeIntervalSince1970
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
