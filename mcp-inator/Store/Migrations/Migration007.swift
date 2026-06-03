import GRDB

enum Migration007 {
    static func register(in migrator: inout DatabaseMigrator) {
        // .immediate avoids the full PRAGMA foreign_key_check that .deferred runs across
        // all tables — which would surface pre-existing violations unrelated to this migration.
        migrator.registerMigration("007_add_unmanaged_keys", foreignKeyChecks: .immediate) { db in
            try db.execute(sql: """
                CREATE TABLE unmanaged_keys (
                    agentId   INTEGER NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
                    serverKey TEXT    NOT NULL,
                    createdAt REAL    NOT NULL,
                    PRIMARY KEY (agentId, serverKey)
                )
            """)
        }
    }
}
