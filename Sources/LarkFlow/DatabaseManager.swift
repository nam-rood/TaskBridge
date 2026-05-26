import Foundation
import GRDB

// 定义任务映射模型
struct TaskMapping: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var feishuTaskId: String
    var appleReminderId: String
    var syncVersion: Int
    var lastUpdated: Date

    // 定义数据库表名
    static let databaseTableName = "task_mapping"
}

// 定义清单(文件夹)映射模型
struct TasklistMapping: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var feishuListId: String
    var feishuSectionId: String // 新增：支持分组级别的映射
    var appleCalendarId: String

    static let databaseTableName = "tasklist_mapping"
}

class DatabaseManager {
    static let shared = DatabaseManager()

    private var dbQueue: DatabaseQueue?

    private init() {
        setupDatabase()
    }

    private func setupDatabase() {
        do {
            // 获取应用的 Application Support 目录用于存放数据库文件
            let fileManager = FileManager.default
            let appSupportURL = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let dbDirectoryURL = appSupportURL.appendingPathComponent("com.namrood.LarkFlow", isDirectory: true)

            if !fileManager.fileExists(atPath: dbDirectoryURL.path) {
                try fileManager.createDirectory(at: dbDirectoryURL, withIntermediateDirectories: true, attributes: nil)
            }

            let dbURL = dbDirectoryURL.appendingPathComponent("larkflow.sqlite")
            print("数据库路径: \(dbURL.path)")

            dbQueue = try DatabaseQueue(path: dbURL.path)

            // 运行数据库迁移（建表）
            try migrator.migrate(dbQueue!)

        } catch {
            print("数据库初始化失败: \(error)")
        }
    }

    // 定义数据库迁移计划
    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: TaskMapping.databaseTableName) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("feishuTaskId", .text).notNull().unique()
                t.column("appleReminderId", .text).notNull().unique()
                t.column("syncVersion", .integer).notNull().defaults(to: 0)
                t.column("lastUpdated", .datetime).notNull()
            }
        }

        migrator.registerMigration("v2") { db in
            try db.create(table: TasklistMapping.databaseTableName) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("feishuListId", .text).notNull()
                t.column("feishuSectionId", .text).notNull().defaults(to: "")
                t.column("appleCalendarId", .text).notNull().unique()
                // 复合唯一约束：一个清单的一个分组，只能映射到一个 Apple 列表
                t.uniqueKey(["feishuListId", "feishuSectionId"])
            }
        }

        return migrator
    }

    // MARK: - 数据库操作方法

    func saveMapping(feishuId: String, appleId: String, version: Int = 0) {
        do {
            try dbQueue?.write { db in
                let mapping = TaskMapping(
                    feishuTaskId: feishuId,
                    appleReminderId: appleId,
                    syncVersion: version,
                    lastUpdated: Date()
                )
                try mapping.insert(db)
            }
            print("保存映射成功: \(feishuId) <-> \(appleId)")
        } catch {
            print("保存映射失败: \(error)")
        }
    }

    func getMapping(byFeishuId feishuId: String) -> TaskMapping? {
        do {
            return try dbQueue?.read { db in
                try TaskMapping.filter(Column("feishuTaskId") == feishuId).fetchOne(db)
            }
        } catch {
            print("查询映射失败: \(error)")
            return nil
        }
    }

    func getMapping(byAppleId appleId: String) -> TaskMapping? {
        do {
            return try dbQueue?.read { db in
                try TaskMapping.filter(Column("appleReminderId") == appleId).fetchOne(db)
            }
        } catch {
            print("查询映射失败: \(error)")
            return nil
        }
    }

    // MARK: - 清单映射操作

    func saveListMapping(feishuListId: String, feishuSectionId: String = "", appleId: String) {
        do {
            try dbQueue?.write { db in
                let mapping = TasklistMapping(feishuListId: feishuListId, feishuSectionId: feishuSectionId, appleCalendarId: appleId)
                try mapping.insert(db)
            }
        } catch {
            print("保存清单映射失败: \(error)")
        }
    }

    func getListMapping(byFeishuListId listId: String, sectionId: String = "") -> TasklistMapping? {
        do {
            return try dbQueue?.read { db in
                try TasklistMapping.filter(Column("feishuListId") == listId && Column("feishuSectionId") == sectionId).fetchOne(db)
            }
        } catch {
            return nil
        }
    }
}