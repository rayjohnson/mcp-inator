import GRDB

enum Migration001 {
    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("001_initial") { db in
            try db.execute(sql: """
                CREATE TABLE mcp_server_configs (
                    id          INTEGER PRIMARY KEY AUTOINCREMENT,
                    uuid        TEXT    NOT NULL UNIQUE,
                    displayName TEXT    NOT NULL,
                    serverKey   TEXT    NOT NULL,
                    command     TEXT    NOT NULL,
                    args        TEXT    NOT NULL DEFAULT '[]',
                    envVars     TEXT    NOT NULL DEFAULT '[]',
                    notes       TEXT    NOT NULL DEFAULT '',
                    createdAt   REAL    NOT NULL,
                    updatedAt   REAL    NOT NULL
                );

                CREATE TABLE agents (
                    id            INTEGER PRIMARY KEY AUTOINCREMENT,
                    agentType     TEXT    NOT NULL,
                    displayName   TEXT    NOT NULL,
                    configPath    TEXT    NOT NULL,
                    isCustomPath  INTEGER NOT NULL DEFAULT 0,
                    isAvailable   INTEGER NOT NULL DEFAULT 1,
                    discoveredAt  REAL    NOT NULL,
                    lastSeenAt    REAL    NOT NULL
                );

                CREATE TABLE config_agent_assignments (
                    id                   INTEGER PRIMARY KEY AUTOINCREMENT,
                    configUUID           TEXT    NOT NULL REFERENCES mcp_server_configs(uuid) ON DELETE CASCADE,
                    agentId              INTEGER NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
                    state                TEXT    NOT NULL DEFAULT 'disabled',
                    lastWrittenSnapshot  TEXT,
                    assignedAt           REAL    NOT NULL,
                    updatedAt            REAL    NOT NULL,
                    UNIQUE(configUUID, agentId)
                );

                CREATE INDEX idx_assignments_configUUID ON config_agent_assignments(configUUID);
                CREATE INDEX idx_assignments_agentId    ON config_agent_assignments(agentId);
            """)
        }
    }
}
