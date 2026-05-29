import GRDB

enum Migration006 {
    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("006_add_is_private") { db in
            try db.alter(table: "mcp_server_configs") { t in
                t.add(column: "isPrivate", .boolean).notNull().defaults(to: false)
            }
        }
    }
}
