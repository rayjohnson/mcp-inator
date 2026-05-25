import GRDB

enum Migration002 {
    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("002_agent_notes") { db in
            try db.execute(sql: """
                ALTER TABLE agents ADD COLUMN notes TEXT NOT NULL DEFAULT '';
            """)
        }
    }
}
