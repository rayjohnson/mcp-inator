import GRDB

enum Migration007 {
    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("007_add_unmanaged_keys") { db in
            try db.create(table: "unmanaged_keys") { tbl in
                tbl.column("agentId", .integer).notNull().references("agents", onDelete: .cascade)
                tbl.column("serverKey", .text).notNull()
                tbl.column("createdAt", .double).notNull()
                tbl.primaryKey(["agentId", "serverKey"])
            }
        }
    }
}
