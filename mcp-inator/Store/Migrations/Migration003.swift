import GRDB

enum Migration003 {
    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("003_transport_type") { db in
            try db.execute(sql: """
                ALTER TABLE mcp_server_configs
                    ADD COLUMN transportType TEXT NOT NULL DEFAULT 'stdio';
            """)
            try db.execute(sql: """
                ALTER TABLE mcp_server_configs
                    ADD COLUMN url TEXT NOT NULL DEFAULT '';
            """)
        }
    }
}
