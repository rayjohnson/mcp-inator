import GRDB

enum Migration005 {
    static func register(in migrator: inout DatabaseMigrator) {
        // Clear stale lastWrittenSnapshot values for built-in servers.
        // The built-in server (mcp-inator) stores command="" in the DB but the real
        // executable path is resolved at runtime. Old snapshots may have been written
        // with the path before a config-map bug was fixed, leaving snapshots that no
        // longer match what is on disk. Clearing them removes drift detection for
        // mcp-inator until it is next explicitly enabled.
        migrator.registerMigration("005_clear_builtin_snapshots") { db in
            try db.execute(sql: """
                UPDATE config_agent_assignments
                SET lastWrittenSnapshot = NULL
                WHERE configUUID IN (
                    SELECT uuid FROM mcp_server_configs WHERE serverKey = 'mcp-inator'
                )
            """)
        }
    }
}
