import Foundation
import GRDB

// 定义任务映射模型
struct TaskMapping: Codable, FetchableRecord, PersistableRecord {
    var id: Int64? = nil
    var feishuTaskId: String
    var appleReminderId: String
    var syncVersion: Int
    var lastUpdated: Date
    var lastTitle: String?
    var lastCompleted: Bool?
    var lastDueTimestamp: String?
    var lastSyncSource: String?
    var lastAppleCalendarId: String?

    static let databaseTableName = "task_mapping"
}

// 定义清单(文件夹)映射模型
struct TasklistMapping: Codable, FetchableRecord, PersistableRecord {
    var id: Int64? = nil
    var feishuListId: String
    var feishuSectionId: String // 新增：支持分组级别的映射
    var appleCalendarId: String

    static let databaseTableName = "tasklist_mapping"
}

class DatabaseManager {
    static let shared = DatabaseManager()

    private let legacyMigrationKey = "didMigrateLarkFlowDatabaseToTaskBridge"
    private var dbQueue: DatabaseQueue?

    private init() {
        setupDatabase()
    }

    private func setupDatabase() {
        do {
            // 获取应用的 Application Support 目录用于存放数据库文件
            let fileManager = FileManager.default
            let appSupportURL = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let dbDirectoryURL = appSupportURL.appendingPathComponent("com.namrood.TaskBridge", isDirectory: true)

            if !fileManager.fileExists(atPath: dbDirectoryURL.path) {
                try fileManager.createDirectory(at: dbDirectoryURL, withIntermediateDirectories: true, attributes: nil)
            }

            let dbURL = dbDirectoryURL.appendingPathComponent("taskbridge.sqlite")
            try migrateLegacyDatabaseIfNeeded(fileManager: fileManager, appSupportURL: appSupportURL, destinationURL: dbURL)
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

        migrator.registerMigration("v3") { db in
            try db.alter(table: TaskMapping.databaseTableName) { t in
                t.add(column: "lastTitle", .text)
                t.add(column: "lastCompleted", .boolean)
                t.add(column: "lastDueTimestamp", .text)
                t.add(column: "lastSyncSource", .text)
            }
        }

        migrator.registerMigration("v4") { db in
            try db.alter(table: TaskMapping.databaseTableName) { t in
                t.add(column: "lastAppleCalendarId", .text)
            }
        }

        return migrator
    }

    private func migrateLegacyDatabaseIfNeeded(fileManager: FileManager, appSupportURL: URL, destinationURL: URL) throws {
        guard !UserDefaults.standard.bool(forKey: legacyMigrationKey) else { return }

        let legacyDirectoryURL = appSupportURL.appendingPathComponent("com.namrood.LarkFlow", isDirectory: true)
        let legacyURL = legacyDirectoryURL.appendingPathComponent("larkflow.sqlite")
        guard fileManager.fileExists(atPath: legacyURL.path) else { return }

        let timestamp = Int(Date().timeIntervalSince1970)
        for suffix in ["", "-wal", "-shm"] {
            let destinationSidecarURL = URL(fileURLWithPath: destinationURL.path + suffix)
            if fileManager.fileExists(atPath: destinationSidecarURL.path) {
                let backupURL = destinationURL.deletingLastPathComponent().appendingPathComponent("taskbridge.sqlite.pre-migration-backup-\(timestamp)\(suffix)")
                try fileManager.moveItem(at: destinationSidecarURL, to: backupURL)
                print("已备份 TaskBridge 数据库: \(backupURL.path)")
            }

            let legacySidecarURL = URL(fileURLWithPath: legacyURL.path + suffix)
            if fileManager.fileExists(atPath: legacySidecarURL.path) {
                try fileManager.copyItem(at: legacySidecarURL, to: destinationSidecarURL)
            }
        }

        UserDefaults.standard.set(true, forKey: legacyMigrationKey)
        print("已从旧 LarkFlow 数据库迁移同步映射")
    }

    // MARK: - 数据库操作方法

    func saveMapping(feishuId: String, appleId: String, version: Int = 0, title: String? = nil, completed: Bool? = nil, dueTimestamp: String? = nil, appleCalendarId: String? = nil, source: String? = nil) {
        do {
            try dbQueue?.write { db in
                try db.execute(
                    sql: """
                    DELETE FROM task_mapping
                    WHERE (feishuTaskId = ? OR appleReminderId = ?)
                      AND NOT (feishuTaskId = ? AND appleReminderId = ?)
                    """,
                    arguments: [feishuId, appleId, feishuId, appleId]
                )

                try db.execute(
                    sql: """
                    INSERT INTO task_mapping (feishuTaskId, appleReminderId, syncVersion, lastUpdated, lastTitle, lastCompleted, lastDueTimestamp, lastSyncSource, lastAppleCalendarId)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(feishuTaskId) DO UPDATE SET
                        appleReminderId = excluded.appleReminderId,
                        syncVersion = excluded.syncVersion,
                        lastUpdated = excluded.lastUpdated,
                        lastTitle = COALESCE(excluded.lastTitle, task_mapping.lastTitle),
                        lastCompleted = COALESCE(excluded.lastCompleted, task_mapping.lastCompleted),
                        lastDueTimestamp = COALESCE(excluded.lastDueTimestamp, task_mapping.lastDueTimestamp),
                        lastSyncSource = COALESCE(excluded.lastSyncSource, task_mapping.lastSyncSource),
                        lastAppleCalendarId = COALESCE(excluded.lastAppleCalendarId, task_mapping.lastAppleCalendarId)
                    """,
                    arguments: [feishuId, appleId, version, Date(), title, completed, dueTimestamp, source, appleCalendarId]
                )
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

    func getAllMappings() -> [TaskMapping] {
        do {
            return try dbQueue?.read { db in
                try TaskMapping.fetchAll(db)
            } ?? []
        } catch {
            print("查询全部映射失败: \(error)")
            return []
        }
    }

    func deleteMapping(feishuId: String) {
        do {
            try dbQueue?.write { db in
                try db.execute(
                    sql: "DELETE FROM task_mapping WHERE feishuTaskId = ?",
                    arguments: [feishuId]
                )
            }
        } catch {
            print("删除映射失败: \(error)")
        }
    }

    func deleteMapping(appleId: String) {
        do {
            try dbQueue?.write { db in
                try db.execute(
                    sql: "DELETE FROM task_mapping WHERE appleReminderId = ?",
                    arguments: [appleId]
                )
            }
        } catch {
            print("删除映射失败: \(error)")
        }
    }

    func updateSnapshot(feishuId: String, title: String, completed: Bool, dueTimestamp: String?, appleCalendarId: String? = nil, source: String) {
        do {
            try dbQueue?.write { db in
                try db.execute(
                    sql: """
                    UPDATE task_mapping
                    SET lastTitle = ?, lastCompleted = ?, lastDueTimestamp = ?, lastSyncSource = ?, lastAppleCalendarId = COALESCE(?, lastAppleCalendarId), lastUpdated = ?
                    WHERE feishuTaskId = ?
                    """,
                    arguments: [title, completed, dueTimestamp, source, appleCalendarId, Date(), feishuId]
                )
            }
        } catch {
            print("更新同步快照失败: \(error)")
        }
    }

    // MARK: - 清单映射操作

    func saveListMapping(feishuListId: String, feishuSectionId: String = "", appleId: String) {
        do {
            try dbQueue?.write { db in
                try db.execute(
                    sql: """
                    INSERT INTO tasklist_mapping (feishuListId, feishuSectionId, appleCalendarId)
                    VALUES (?, ?, ?)
                    ON CONFLICT(feishuListId, feishuSectionId) DO UPDATE SET
                        appleCalendarId = excluded.appleCalendarId
                    """,
                    arguments: [feishuListId, feishuSectionId, appleId]
                )
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

    func getAllListMappings() -> [TasklistMapping] {
        do {
            return try dbQueue?.read { db in
                try TasklistMapping.fetchAll(db)
            } ?? []
        } catch {
            print("查询全部清单映射失败: \(error)")
            return []
        }
    }

    func getListMapping(byAppleCalendarId appleCalendarId: String) -> TasklistMapping? {
        do {
            return try dbQueue?.read { db in
                try TasklistMapping.filter(Column("appleCalendarId") == appleCalendarId).fetchOne(db)
            }
        } catch {
            print("按 Apple 列表查询清单映射失败: \(error)")
            return nil
        }
    }
}