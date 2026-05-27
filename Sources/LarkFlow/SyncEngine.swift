import Foundation
import EventKit

class SyncEngine {
    static let shared = SyncEngine()

    private let feishuAPI = FeishuAPIClient.shared
    private let dbManager = DatabaseManager.shared
    private let eventKitManager = EventKitManager.shared
    let viewModel = TaskViewModel()

    private var isSyncing = false
    private var autoSyncTimer: Timer?
    private let autoSyncInterval: TimeInterval = 120

    private init() {}

    func startAutomaticSync() {
        DispatchQueue.main.async {
            self.autoSyncTimer?.invalidate()

            let timer = Timer(timeInterval: self.autoSyncInterval, repeats: true) { [weak self] _ in
                self?.syncBidirectionally { _, _ in }
            }
            timer.tolerance = min(15, self.autoSyncInterval * 0.2)

            RunLoop.main.add(timer, forMode: .common)
            self.autoSyncTimer = timer
            print("🕒 已启动自动同步，间隔 \(Int(self.autoSyncInterval)) 秒")
        }
    }

    func stopAutomaticSync() {
        DispatchQueue.main.async {
            self.autoSyncTimer?.invalidate()
            self.autoSyncTimer = nil
        }
    }

    func syncBidirectionally(completion: @escaping (Bool, String) -> Void) {
        let defaults = UserDefaults.standard
        defaults.set(ISO8601DateFormatter().string(from: Date()), forKey: "debugLastBidirectionalSyncAt")

        guard eventKitManager.isAuthorized else {
            defaults.set("missing_reminders_permission", forKey: "debugLastBidirectionalSyncResult")
            completion(false, "未获取提醒事项权限")
            return
        }

        guard feishuAPI.userAccessToken != nil else {
            defaults.set("missing_feishu_token", forKey: "debugLastBidirectionalSyncResult")
            completion(false, "未登录飞书")
            return
        }

        syncFeishuToApple { success, message in
            guard success else {
                defaults.set("feishu_to_apple_failed: \(message)", forKey: "debugLastBidirectionalSyncResult")
                completion(false, message)
                return
            }

            AppleToFeishuSync.shared.syncAppleToFeishu { appleSuccess, appleMessage in
                let resultMessage = "\(message)；\(appleMessage)"
                defaults.set(appleSuccess ? "success: \(resultMessage)" : "apple_to_feishu_failed: \(resultMessage)", forKey: "debugLastBidirectionalSyncResult")
                if appleSuccess {
                    completion(true, resultMessage)
                } else {
                    completion(false, resultMessage)
                }
            }
        }
    }

    func syncFeishuToApple(completion: @escaping (Bool, String) -> Void) {
        let defaults = UserDefaults.standard
        defaults.set(ISO8601DateFormatter().string(from: Date()), forKey: "debugLastFeishuToAppleAt")

        guard !isSyncing else {
            defaults.set("already_syncing", forKey: "debugLastFeishuToAppleResult")
            completion(false, "同步正在进行中，请稍后再试")
            return
        }

        guard eventKitManager.isAuthorized else {
            defaults.set("missing_reminders_permission", forKey: "debugLastFeishuToAppleResult")
            completion(false, "未获取提醒事项权限")
            return
        }

        isSyncing = true
        print("🔄 开始同步：飞书 -> Apple Reminders")

        var totalCreated = 0
        var totalUpdated = 0
        var syncErrors: [String] = []
        let group = DispatchGroup()

        group.enter()
        var allTasksCollected: [FeishuTask] = []
        var allSectionsCollected: [FeishuSection] = []

        feishuAPI.fetchTasks(tasklistGuid: nil) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let allTasks):
                allTasksCollected = allTasks
                print("📝 全局获取到 \(allTasks.count) 个任务")

                self.feishuAPI.fetchTasklists { listResult in
                    switch listResult {
                    case .success(let tasklists):
                        print("📁 获取到 \(tasklists.count) 个飞书清单")

                        for tasklist in tasklists {
                            group.enter()
                            self.feishuAPI.fetchSections(tasklistGuid: tasklist.guid) { sectionResult in
                                switch sectionResult {
                                case .success(let sections):
                                    allSectionsCollected.append(contentsOf: sections)
                                    if sections.isEmpty {
                                        let listTasks = allTasks.filter { task in
                                            task.tasklists?.contains(where: { $0.tasklistGuid == tasklist.guid }) ?? false
                                        }
                                        self.syncSection(tasklist: tasklist, section: nil, tasks: listTasks) { created, updated in
                                            totalCreated += created
                                            totalUpdated += updated
                                            group.leave()
                                        }
                                    } else {
                                        let sectionGroup = DispatchGroup()
                                        var createdInSections = 0
                                        var updatedInSections = 0

                                        for section in sections {
                                            sectionGroup.enter()
                                            let sectionTasks = allTasks.filter { task in
                                                task.tasklists?.contains(where: { $0.tasklistGuid == tasklist.guid && $0.sectionGuid == section.guid }) ?? false
                                            }
                                            self.syncSection(tasklist: tasklist, section: section, tasks: sectionTasks) { created, updated in
                                                createdInSections += created
                                                updatedInSections += updated
                                                sectionGroup.leave()
                                            }
                                        }

                                        sectionGroup.notify(queue: .main) {
                                            totalCreated += createdInSections
                                            totalUpdated += updatedInSections
                                            group.leave()
                                        }
                                    }
                                case .failure(let error):
                                    let message = "获取清单 [\(tasklist.name)] 的分组失败: \(error.localizedDescription)"
                                    print("❌ \(message)")
                                    syncErrors.append(message)
                                    group.leave()
                                }
                            }
                        }

                        let independentTasks = allTasks.filter { task in
                            task.tasklists == nil || task.tasklists?.isEmpty == true
                        }

                        if !independentTasks.isEmpty {
                            print("📝 发现 \(independentTasks.count) 个任务归入“我负责的”")
                            if let defaultCalendar = self.eventKitManager.getOrCreateCalendar(title: "飞书 - 我负责的") {
                                self.dbManager.saveListMapping(feishuListId: "", feishuSectionId: "", appleId: defaultCalendar.calendarIdentifier)
                                group.enter()
                                self.processFeishuTasks(independentTasks, in: defaultCalendar) { created, updated in
                                    totalCreated += created
                                    totalUpdated += updated
                                    group.leave()
                                }
                            }
                        }

                    case .failure(let error):
                        let message = "获取飞书清单失败: \(error.localizedDescription)"
                        print("❌ \(message)")
                        syncErrors.append(message)
                    }
                    group.leave()
                }

            case .failure(let error):
                let message = "全局获取任务失败: \(error.localizedDescription)"
                print("❌ \(message)")
                syncErrors.append(message)
                group.leave()
            }
        }

        group.notify(queue: .main) {
            self.viewModel.processTasks(tasks: allTasksCollected, sections: allSectionsCollected)

            guard syncErrors.isEmpty else {
                self.isSyncing = false
                let msg = "同步失败：\(syncErrors[0])"
                defaults.set(msg, forKey: "debugLastFeishuToAppleResult")
                print("❌ \(msg)")
                completion(false, msg)
                return
            }

            let validTaskIds = Set(allTasksCollected.map(\.guid))
            self.cleanupDeletedFeishuMappings(validTaskIds: validTaskIds) { deletedCount, cleanupErrors in
                self.isSyncing = false

                if let firstError = cleanupErrors.first {
                    let msg = "同步失败：\(firstError)"
                    print("❌ \(msg)")
                    completion(false, msg)
                    return
                }

                let msg = "同步完成！新建: \(totalCreated), 更新: \(totalUpdated), 删除: \(deletedCount)"
                defaults.set("success: \(msg)", forKey: "debugLastFeishuToAppleResult")
                print("✅ \(msg)")
                completion(true, msg)
            }
        }
    }

    private func syncSection(tasklist: FeishuTasklist, section: FeishuSection?, tasks: [FeishuTask], completion: @escaping (Int, Int) -> Void) {
        let calendarName: String
        let sectionId: String
        if let section = section {
            calendarName = "飞书 - \(tasklist.name) - \(section.name)"
            sectionId = section.guid
        } else {
            calendarName = "飞书 - \(tasklist.name)"
            sectionId = ""
        }

        guard let calendar = eventKitManager.getOrCreateCalendar(title: calendarName) else {
            completion(0, 0)
            return
        }

        dbManager.saveListMapping(feishuListId: tasklist.guid, feishuSectionId: sectionId, appleId: calendar.calendarIdentifier)
        processFeishuTasks(tasks, in: calendar, completion: completion)
    }

    private func processFeishuTasks(_ tasks: [FeishuTask], in calendar: EKCalendar, completion: @escaping (Int, Int) -> Void) {
        var createdCount = 0
        var updatedCount = 0
        let group = DispatchGroup()

        for task in tasks {
            group.enter()

            if let mapping = dbManager.getMapping(byFeishuId: task.guid) {
                eventKitManager.getReminder(byId: mapping.appleReminderId) { reminder in
                    defer { group.leave() }

                    guard let reminder = reminder else {
                        if self.createNewReminder(for: task, in: calendar) {
                            createdCount += 1
                        }
                        return
                    }

                    let localDue = self.eventKitManager.dueInfo(from: reminder)
                    let localTitleChanged = Self.hasLocalTitleChange(lastTitle: mapping.lastTitle, currentTitle: reminder.title)
                    let localCompletedChanged = Self.hasLocalCompletedChange(lastCompleted: mapping.lastCompleted, currentCompleted: reminder.isCompleted)
                    let localDueChanged = Self.hasLocalDueChange(lastDueTimestamp: mapping.lastDueTimestamp, currentDueTimestamp: localDue?.timestamp)
                    let localCalendarChanged = Self.hasLocalCalendarChange(lastAppleCalendarId: mapping.lastAppleCalendarId, currentAppleCalendarId: reminder.calendar.calendarIdentifier)

                    var needsUpdate = false

                    if !localTitleChanged && reminder.title != task.summary {
                        reminder.title = task.summary
                        needsUpdate = true
                    }

                    let isCompletedInFeishu = task.completedAt != nil && task.completedAt != "0"
                    if !localCompletedChanged && reminder.isCompleted != isCompletedInFeishu {
                        reminder.isCompleted = isCompletedInFeishu
                        needsUpdate = true
                    }

                    if !localDueChanged && localDue?.timestamp != task.due?.timestamp {
                        self.eventKitManager.applyDue(timestamp: task.due?.timestamp, isAllDay: task.due?.isAllDay ?? false, to: reminder)
                        needsUpdate = true
                    }

                    if !localCalendarChanged && reminder.calendar.calendarIdentifier != calendar.calendarIdentifier {
                        reminder.calendar = calendar
                        needsUpdate = true
                    }

                    if needsUpdate {
                        SyncState.shared.isApplyingRemoteChanges = true
                        let saved = self.eventKitManager.saveReminder(reminder)
                        SyncState.shared.isApplyingRemoteChanges = false

                        guard saved else { return }

                        updatedCount += 1
                        self.dbManager.updateSnapshot(
                            feishuId: task.guid,
                            title: reminder.title,
                            completed: reminder.isCompleted,
                            dueTimestamp: self.eventKitManager.dueInfo(from: reminder)?.timestamp,
                            appleCalendarId: reminder.calendar.calendarIdentifier,
                            source: "feishu"
                        )
                    }
                }
            } else {
                if createNewReminder(for: task, in: calendar) {
                    createdCount += 1
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(createdCount, updatedCount)
        }
    }

    private func cleanupDeletedFeishuMappings(validTaskIds: Set<String>, completion: @escaping (Int, [String]) -> Void) {
        let staleMappings = dbManager.getAllMappings().filter { !validTaskIds.contains($0.feishuTaskId) }
        guard !staleMappings.isEmpty else {
            completion(0, [])
            return
        }

        var deletedCount = 0
        var errors: [String] = []
        let group = DispatchGroup()

        for mapping in staleMappings {
            group.enter()
            eventKitManager.getReminder(byId: mapping.appleReminderId) { reminder in
                defer { group.leave() }

                if let reminder = reminder {
                    SyncState.shared.isApplyingRemoteChanges = true
                    let removed = self.eventKitManager.removeReminder(reminder)
                    SyncState.shared.isApplyingRemoteChanges = false

                    guard removed else {
                        errors.append("删除提醒事项失败: \(mapping.feishuTaskId)")
                        return
                    }
                    deletedCount += 1
                }

                self.dbManager.deleteMapping(feishuId: mapping.feishuTaskId)
            }
        }

        group.notify(queue: .main) {
            completion(deletedCount, errors)
        }
    }

    private func createNewReminder(for task: FeishuTask, in calendar: EKCalendar) -> Bool {
        let reminder = EKReminder(eventStore: eventKitManager.store)
        reminder.title = task.summary
        reminder.calendar = calendar

        if task.completedAt != nil && task.completedAt != "0" {
            reminder.isCompleted = true
        }
        eventKitManager.applyDue(timestamp: task.due?.timestamp, isAllDay: task.due?.isAllDay ?? false, to: reminder)

        SyncState.shared.isApplyingRemoteChanges = true
        let saved = eventKitManager.saveReminder(reminder)
        SyncState.shared.isApplyingRemoteChanges = false

        guard saved else { return false }

        let isCompletedInFeishu = task.completedAt != nil && task.completedAt != "0"
        dbManager.saveMapping(
            feishuId: task.guid,
            appleId: reminder.calendarItemIdentifier,
            title: task.summary,
            completed: isCompletedInFeishu,
            dueTimestamp: task.due?.timestamp,
            appleCalendarId: calendar.calendarIdentifier,
            source: "feishu"
        )
        print("✨ 新建提醒事项: \(task.summary)")
        return true
    }

    static func hasLocalTitleChange(lastTitle: String?, currentTitle: String) -> Bool {
        guard let lastTitle else { return false }
        return lastTitle != currentTitle
    }

    static func hasLocalCompletedChange(lastCompleted: Bool?, currentCompleted: Bool) -> Bool {
        guard let lastCompleted else { return false }
        return lastCompleted != currentCompleted
    }

    static func hasLocalDueChange(lastDueTimestamp: String?, currentDueTimestamp: String?) -> Bool {
        guard let lastDueTimestamp else {
            return currentDueTimestamp != nil
        }
        return lastDueTimestamp != currentDueTimestamp
    }

    static func hasLocalCalendarChange(lastAppleCalendarId: String?, currentAppleCalendarId: String) -> Bool {
        guard let lastAppleCalendarId else { return false }
        return lastAppleCalendarId != currentAppleCalendarId
    }
}

