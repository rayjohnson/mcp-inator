import Foundation
import GRDB

// Central access layer for the mcp-inator SQLite store.
// All database operations go through here; adapters handle file I/O separately.
@MainActor
final class ConfigStore: ObservableObject {

    // MARK: - Published State

    @Published private(set) var configs: [MCPServerConfig] = []
    @Published private(set) var agents: [AgentRecord] = []

    // MARK: - Private

    private let pool: DatabasePool

    // MARK: - Init

    init() throws {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dbDir = appSupport.appendingPathComponent("mcp-inator")
        try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        let dbURL = dbDir.appendingPathComponent("mcp-inator.db")

        pool = try DatabasePool(path: dbURL.path)
        try runMigrations()
        try reload()
    }

    init(databasePath: URL) throws {
        try FileManager.default.createDirectory(
            at: databasePath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        pool = try DatabasePool(path: databasePath.path)
        try runMigrations()
        try reload()
    }

    // MARK: - Migrations

    private func runMigrations() throws {
        var migrator = DatabaseMigrator()
        Migration001.register(in: &migrator)
        Migration002.register(in: &migrator)
        try migrator.migrate(pool)
    }

    // MARK: - Reload Published State

    func reload() throws {
        configs = try pool.read { db in try MCPServerConfig.fetchAll(db) }
        agents  = try pool.read { db in try AgentRecord.fetchAll(db) }
    }

    // MARK: - MCPServerConfig CRUD (T011)

    func insert(_ config: MCPServerConfig) throws -> MCPServerConfig {
        var record = config
        try pool.write { db in try record.insert(db) }
        try reload()
        return record
    }

    func update(_ config: MCPServerConfig) throws {
        var record = config
        record.updatedAt = Date()
        try pool.write { db in try record.update(db) }
        try reload()
    }

    func delete(_ config: MCPServerConfig) throws {
        try pool.write { db in
            _ = try MCPServerConfig.deleteOne(db, key: config.id)
        }
        try reload()
    }

    func fetch(uuid: UUID) throws -> MCPServerConfig? {
        try pool.read { db in
            try MCPServerConfig.filter(Column("uuid") == uuid.uuidString).fetchOne(db)
        }
    }

    // MARK: - AgentRecord CRUD (T012)

    func upsertAgent(_ agent: AgentRecord) throws -> AgentRecord {
        var record = agent
        try pool.write { db in
            if let existing = try AgentRecord
                .filter(Column("agentType") == record.agentType.rawValue)
                .fetchOne(db) {
                record.id = existing.id
                try record.update(db)
            } else {
                try record.insert(db)
            }
        }
        try reload()
        return record
    }

    func updateAgentAvailability(agentId: Int64, isAvailable: Bool) throws {
        try pool.write { db in
            try db.execute(
                sql: "UPDATE agents SET isAvailable = ?, lastSeenAt = ? WHERE id = ?",
                arguments: [isAvailable ? 1 : 0, Date().timeIntervalSince1970, agentId]
            )
        }
        try reload()
    }

    func updateAgentConfigPath(agentId: Int64, path: String) throws {
        try pool.write { db in
            try db.execute(
                sql: "UPDATE agents SET configPath = ?, isCustomPath = 1 WHERE id = ?",
                arguments: [path, agentId]
            )
        }
        try reload()
    }

    // MARK: - Assignments (T012)

    func fetchAssignment(configUUID: UUID, agentId: Int64) throws -> ConfigAgentAssignment? {
        try pool.read { db in
            try ConfigAgentAssignment
                .filter(Column("configUUID") == configUUID.uuidString)
                .filter(Column("agentId") == agentId)
                .fetchOne(db)
        }
    }

    func fetchEnabledConfigs(for agentId: Int64) throws -> [MCPServerConfig] {
        try pool.read { db in
            let uuids = try ConfigAgentAssignment
                .filter(Column("agentId") == agentId)
                .filter(Column("state") == AssignmentState.enabled.rawValue)
                .fetchAll(db)
                .map(\.configUUID.uuidString)
            return try MCPServerConfig
                .filter(uuids.contains(Column("uuid")))
                .fetchAll(db)
        }
    }

    func setAssignmentState(
        configUUID: UUID,
        agentId: Int64,
        state: AssignmentState,
        snapshot: MCPServerConfig? = nil
    ) throws {
        try pool.write { db in
            if var existing = try ConfigAgentAssignment
                .filter(Column("configUUID") == configUUID.uuidString)
                .filter(Column("agentId") == agentId)
                .fetchOne(db) {
                existing.state = state
                existing.updatedAt = Date()
                if let snap = snapshot { existing.lastWrittenSnapshot = snap }
                try existing.update(db)
            } else {
                var assignment = ConfigAgentAssignment(configUUID: configUUID, agentId: agentId, state: state)
                assignment.lastWrittenSnapshot = snapshot
                try assignment.insert(db)
            }
        }
    }

    // MARK: - Enable / Disable Config for Agent (T036, T037)

    func enableConfig(
        uuid: UUID,
        agentId: Int64,
        adapter: any AgentAdapter,
        configPath: URL,
        force: Bool = false
    ) throws -> WriteResult {
        guard let config = try fetch(uuid: uuid) else {
            throw AdapterError.parseFailure(configPath, underlying: NSError(domain: "ConfigStore", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Config not found: \(uuid)"]))
        }

        let enabledConfigs = try fetchEnabledConfigs(for: agentId)
        var configMap: [String: MCPServerConfig] = Dictionary(
            uniqueKeysWithValues: enabledConfigs.map { ($0.serverKey, $0) }
        )
        configMap[config.serverKey] = config

        // Build expectedExisting from lastWrittenSnapshots of enabled assignments
        var expectedExisting: [String: MCPServerConfig]? = nil
        if !force {
            var snapshots: [String: MCPServerConfig] = [:]
            for cfg in enabledConfigs {
                if let assignment = try fetchAssignment(configUUID: cfg.uuid, agentId: agentId),
                   let snapshot = assignment.lastWrittenSnapshot {
                    snapshots[cfg.serverKey] = snapshot
                }
            }
            if !snapshots.isEmpty { expectedExisting = snapshots }
        }

        let result = try adapter.writeConfigs(configMap, to: configPath,
                                              expectedExisting: force ? nil : expectedExisting)
        if case .success = result {
            try setAssignmentState(configUUID: uuid, agentId: agentId,
                                   state: .enabled, snapshot: config)
        }
        return result
    }

    func disableConfig(
        uuid: UUID,
        agentId: Int64,
        adapter: any AgentAdapter,
        configPath: URL,
        force: Bool = false
    ) throws -> WriteResult {
        guard let config = try fetch(uuid: uuid) else {
            throw AdapterError.parseFailure(configPath, underlying: NSError(domain: "ConfigStore", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Config not found: \(uuid)"]))
        }

        let expectedValue: MCPServerConfig?
        if !force, let assignment = try fetchAssignment(configUUID: uuid, agentId: agentId) {
            expectedValue = assignment.lastWrittenSnapshot
        } else {
            expectedValue = nil
        }

        let result = try adapter.removeConfig(key: config.serverKey, from: configPath,
                                              expectedValue: force ? nil : expectedValue)
        if case .success = result {
            try setAssignmentState(configUUID: uuid, agentId: agentId,
                                   state: .disabled, snapshot: nil)
        }
        return result
    }

    // MARK: - Discovery (T030)

    struct DiscoveryResult {
        let agent: AgentRecord
        let isNew: Bool
    }

    func discoverAgents(adapters: [any AgentAdapter]) throws -> [DiscoveryResult] {
        var results: [DiscoveryResult] = []
        for adapter in adapters {
            let isInstalled = adapter.isInstalled()
            let existsInDB = try pool.read { db in
                try AgentRecord.filter(Column("agentType") == adapter.agentType.rawValue).fetchOne(db) != nil
            }
            if isInstalled {
                var record = AgentRecord(agentType: adapter.agentType)
                record.isAvailable = true
                let upserted = try upsertAgent(record)
                results.append(DiscoveryResult(agent: upserted, isNew: !existsInDB))
            }
        }
        return results
    }

    // MARK: - Availability Refresh (T043)

    func refreshAvailability(adapters: [any AgentAdapter]) throws {
        for agent in agents {
            guard let adapter = adapters.first(where: { $0.agentType == agent.agentType }),
                  let agentId = agent.id else { continue }
            let available = adapter.isInstalled()
            try updateAgentAvailability(agentId: agentId, isAvailable: available)
        }
        try reload()
    }

    // MARK: - Import Categorisation (T035)

    enum ImportCategory {
        case new(MCPServerConfig)
        case exactMatch(MCPServerConfig)
        case conflict(library: MCPServerConfig, onDisk: MCPServerConfig)
    }

    func categorizeImport(
        from adapter: any AgentAdapter,
        configPath: URL
    ) throws -> [(key: String, category: ImportCategory)] {
        let onDiskConfigs = try adapter.readConfigs(from: configPath)
        var results: [(key: String, category: ImportCategory)] = []

        for (key, onDisk) in onDiskConfigs {
            if let library = try pool.read({ db in
                try MCPServerConfig.filter(Column("serverKey") == key).fetchOne(db)
            }) {
                if library == onDisk {
                    results.append((key, .exactMatch(library)))
                } else {
                    results.append((key, .conflict(library: library, onDisk: onDisk)))
                }
            } else {
                results.append((key, .new(onDisk)))
            }
        }
        return results
    }

    // MARK: - Apply Import Decisions (T054)

    func applyImportDecisions(
        _ decisions: [(key: String, config: MCPServerConfig)],
        agentId: Int64
    ) throws {
        for (_, config) in decisions {
            if let existing = try pool.read({ db in
                try MCPServerConfig.filter(Column("serverKey") == config.serverKey).fetchOne(db)
            }) {
                var updated = config
                updated.id = existing.id
                updated.uuid = existing.uuid
                try update(updated)
                try setAssignmentState(
                    configUUID: existing.uuid, agentId: agentId,
                    state: .enabled, snapshot: updated
                )
            } else {
                let inserted = try insert(config)
                try setAssignmentState(
                    configUUID: inserted.uuid, agentId: agentId,
                    state: .enabled, snapshot: inserted
                )
            }
        }
    }

    // MARK: - Status Matrix (T055)

    struct StatusRow {
        let config: MCPServerConfig
        let agentStates: [(agent: AgentRecord, state: EffectiveState)]
    }

    func fetchStatusMatrix() throws -> [StatusRow] {
        try pool.read { db in
            let allConfigs = try MCPServerConfig.fetchAll(db)
            let allAgents  = try AgentRecord.fetchAll(db)
            let allAssignments = try ConfigAgentAssignment.fetchAll(db)

            return allConfigs.map { config in
                let states: [(agent: AgentRecord, state: EffectiveState)] = allAgents.map { agent in
                    let assignment = allAssignments.first {
                        $0.configUUID == config.uuid && $0.agentId == agent.id
                    }
                    let state: EffectiveState
                    if !agent.isAvailable {
                        state = .unavailable(reason: "Config file not accessible at \(agent.configPath)")
                    } else if assignment?.state == .enabled {
                        state = .enabled
                    } else {
                        state = .disabled
                    }
                    return (agent: agent, state: state)
                }
                return StatusRow(config: config, agentStates: states)
            }
        }
    }

    // MARK: - Enabled Agents for a Config (T049)

    func findEnabledAgents(for configUUID: UUID) throws -> [AgentRecord] {
        try pool.read { db in
            let agentIds = try ConfigAgentAssignment
                .filter(Column("configUUID") == configUUID.uuidString)
                .filter(Column("state") == AssignmentState.enabled.rawValue)
                .fetchAll(db)
                .map(\.agentId)
            return try AgentRecord
                .filter(agentIds.contains(Column("id")))
                .fetchAll(db)
        }
    }

    // MARK: - Bulk Enable (T046)

    struct BulkEnableResult {
        let succeeded: [UUID]
        let failed: [(uuid: UUID, error: Error)]
        let driftDetected: [(uuid: UUID, result: WriteResult)]
    }

    func bulkEnableConfigs(
        uuids: [UUID],
        agentId: Int64,
        adapter: any AgentAdapter,
        configPath: URL
    ) throws -> BulkEnableResult {
        var succeeded: [UUID] = []
        var failed: [(UUID, Error)] = []
        var drifted: [(UUID, WriteResult)] = []

        for uuid in uuids {
            do {
                let result = try enableConfig(uuid: uuid, agentId: agentId,
                                              adapter: adapter, configPath: configPath)
                switch result {
                case .success:
                    succeeded.append(uuid)
                case .driftDetected:
                    drifted.append((uuid, result))
                }
            } catch {
                failed.append((uuid, error))
            }
        }
        return BulkEnableResult(succeeded: succeeded, failed: failed, driftDetected: drifted)
    }
}
