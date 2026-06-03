import GRDB

enum Migration007 {
    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("007_add_unmanaged_keys") { db in
            try db.create(table: "unmanaged_keys") { t in
                t.column("agentId", .integer).notNull().references("agents", onDelete: .cascade)
                t.column("serverKey", .text).notNull()
                t.column("createdAt", .double).notNull()
                t.primaryKey(["agentId", "serverKey"])
            }
        }
    }
}
