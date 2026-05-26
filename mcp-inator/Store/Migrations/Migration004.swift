import GRDB

enum Migration004 {
    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("004_agent_visibility") { db in
            try db.execute(sql: """
                ALTER TABLE agents
                    ADD COLUMN isVisible INTEGER NOT NULL DEFAULT 1;
            """)
        }
    }
}
