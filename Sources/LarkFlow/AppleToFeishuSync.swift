import Foundation
import EventKit

class SyncState {
    static let shared = SyncState()

    var isApplyingRemoteChanges = false

    private init() {}
}

class AppleToFeishuSync {
    static let shared = AppleToFeishuSync()

    private let feishuAPI = FeishuAPIClient.shared
    private let dbManager = DatabaseManager.shared
    private let eventKitManager = EventKitManager.shared
    private var debounceWorkItem: DispatchWorkItem?
    private var isSyncingAppleToFeishu = false
    private var pendingAppleReminderIds = Set<String>()

    private init() {
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: .EKEventStoreChanged, object: nil)
    }

    @objc private func storeChanged() {
        guard !SyncState.shared.isApplyingRemoteChanges else { return }
        guard eventKitManager.isAuthorized else { return }
        guard feishuAPI.userAccessToken != nil else { return }

        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.syncAppleToFeishu(completion: nil)
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
    }

    func syncAppleToFeishu(completion: ((Bool, String) -> Void)? = nil) {
        guard !SyncState.shared.isApplyingRemoteChanges else {
            completion?(false, "正在应用飞书侧变更，稍后再试")
            return
        }
        guard !isSyncingAppleToFeishu else {
            completion?(false, "Apple 到飞书同步正在进行中")
            return
        }
        guard eventKitManager.isAuthorized else {
            completion?(false, "未获取提醒事项权限")
            return
        }
        guard feishuAPI.userAccessToken != nil else {
            completion?(false, "未登录飞书")
            return
        }

        isSyncingAppleToFeishu = true
        syncExistingMappedReminders { [weak self] updatedCount, deletedCount, syncErrors in
            guard let self = self else { return }
            self.syncNewRemindersInManagedCalendars { createdCount, createErrors in
                self.isSyncingAppleToFeishu = false

                let allErrors = syncErrors + createErrors
                if let firstError = allErrors.first {
                    completion?(false, "Apple → 飞书同步失败：\(firstError)")
                    return
                }

                completion?(true, "Apple → 飞书完成！新建: \(createdCount), 更新: \(updatedCount), 删除: \(deletedCount)")
            }
        }
    }

    private func syncExistingMappedReminders(completion: @escaping (Int, Int, [String]) -> Void) {
        let mappings = dbManager.getAllMappings()
        guard !mappings.isEmpty else {
            completion(0, 0, [])
            return
        }

        print("🔄 检查 Apple Reminders 本地变更，共 \(mappings.count) 个映射")

        var updatedCount = 0
        var deletedCount = 0
        var errors: [String] = []
        let group = DispatchGroup()

        for mapping in mappings {
            group.enter()
            eventKitManager.getReminder(byId: mapping.appleReminderId) { [weak self] reminder in
                guard let self = self else {
                    group.leave()
                    return
                }

                guard let reminder = reminder else {
                    self.feishuAPI.deleteTask(guid: mapping.feishuTaskId) { result in
                        switch result {
                        case .success:
                            self.dbManager.deleteMapping(feishuId: mapping.feishuTaskId)
                            deletedCount += 1
                            print("🗑️ 已同步 Apple 删除到飞书: \(mapping.feishuTaskId)")
                        case .failure(let error):
                            errors.append("删除飞书任务失败: \(error.localizedDescription)")
                        }
                        group.leave()
                    }
                    return
                }

                let title = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let due = self.eventKitManager.dueInfo(from: reminder)
                let titleChanged = mapping.lastTitle != title
                let completedChanged = mapping.lastCompleted != reminder.isCompleted
                let dueChanged = mapping.lastDueTimestamp != due?.timestamp
                let summaryToUpdate = (titleChanged && !title.isEmpty) ? title : nil

                guard titleChanged || completedChanged || dueChanged else {
                    group.leave()
                    return
                }

                if titleChanged && title.isEmpty {
                    errors.append("提醒事项标题为空，无法同步到飞书")
                    group.leave()
                    return
                }

                self.feishuAPI.updateTask(
                    guid: mapping.feishuTaskId,
                    summary: summaryToUpdate,
                    isCompleted: completedChanged ? reminder.isCompleted : nil,
                    dueTimestamp: due?.timestamp,
                    isAllDay: due?.isAllDay ?? false,
                    shouldUpdateDue: dueChanged
                ) { result in
                    switch result {
                    case .success:
                        self.dbManager.updateSnapshot(
                            feishuId: mapping.feishuTaskId,
                            title: title,
                            completed: reminder.isCompleted,
                            dueTimestamp: due?.timestamp,
                            appleCalendarId: reminder.calendar.calendarIdentifier,
                            source: "apple"
                        )
                        updatedCount += 1
                        print("✅ 已同步 Apple 变更到飞书: \(title)")
                    case .failure(let error):
                        errors.append("同步 Apple 变更到飞书失败: \(error.localizedDescription)")
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            completion(updatedCount, deletedCount, errors)
        }
    }

    private func syncNewRemindersInManagedCalendars(completion: @escaping (Int, [String]) -> Void) {
        var listMappings = dbManager.getAllListMappings()
        if let independentCalendar = eventKitManager.getCalendar(title: "飞书 - 我负责的") {
            dbManager.saveListMapping(feishuListId: "", feishuSectionId: "", appleId: independentCalendar.calendarIdentifier)
            if !listMappings.contains(where: { $0.appleCalendarId == independentCalendar.calendarIdentifier }) {
                listMappings.append(TasklistMapping(feishuListId: "", feishuSectionId: "", appleCalendarId: independentCalendar.calendarIdentifier))
            }
        }

        guard !listMappings.isEmpty else {
            completion(0, [])
            return
        }

        let calendars = listMappings.compactMap { eventKitManager.getCalendar(byId: $0.appleCalendarId) }
        guard !calendars.isEmpty else {
            completion(0, [])
            return
        }

        eventKitManager.fetchReminders(in: calendars) { [weak self] reminders in
            guard let self = self else {
                completion(0, [])
                return
            }

            let unmappedReminders = reminders.filter { reminder in
                self.dbManager.getMapping(byAppleId: reminder.calendarItemIdentifier) == nil
            }

            guard !unmappedReminders.isEmpty else {
                completion(0, [])
                return
            }

            var createdCount = 0
            var errors: [String] = []
            let group = DispatchGroup()

            for reminder in unmappedReminders {
                guard let calendar = reminder.calendar,
                      let listMapping = self.dbManager.getListMapping(byAppleCalendarId: calendar.calendarIdentifier) else {
                    continue
                }

                group.enter()
                self.createFeishuTaskIfNeeded(from: reminder, listMapping: listMapping) { success, errorMessage in
                    if success {
                        createdCount += 1
                    } else if let errorMessage = errorMessage {
                        errors.append(errorMessage)
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                completion(createdCount, errors)
            }
        }
    }

    private func createFeishuTaskIfNeeded(from reminder: EKReminder, listMapping: TasklistMapping, completion: @escaping (Bool, String?) -> Void) {
        let appleId = reminder.calendarItemIdentifier
        guard dbManager.getMapping(byAppleId: appleId) == nil else {
            completion(false, nil)
            return
        }
        guard !pendingAppleReminderIds.contains(appleId) else {
            completion(false, nil)
            return
        }

        let title = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            completion(false, nil)
            return
        }

        pendingAppleReminderIds.insert(appleId)
        let due = eventKitManager.dueInfo(from: reminder)
        let sectionGuid = listMapping.feishuSectionId.isEmpty ? nil : listMapping.feishuSectionId

        feishuAPI.createTask(
            summary: title,
            tasklistGuid: listMapping.feishuListId,
            sectionGuid: sectionGuid,
            dueTimestamp: due?.timestamp,
            isAllDay: due?.isAllDay ?? false
        ) { [weak self] result in
            guard let self = self else {
                completion(false, nil)
                return
            }

            defer {
                self.pendingAppleReminderIds.remove(appleId)
            }

            switch result {
            case .success(let createdTask):
                self.dbManager.saveMapping(
                    feishuId: createdTask.guid,
                    appleId: appleId,
                    title: title,
                    completed: reminder.isCompleted,
                    dueTimestamp: due?.timestamp,
                    appleCalendarId: reminder.calendar.calendarIdentifier,
                    source: "apple"
                )
                print("✅ 已从 Apple 新建飞书任务: \(title)")

                if reminder.isCompleted {
                    self.feishuAPI.updateTaskStatus(guid: createdTask.guid, isCompleted: true) { statusResult in
                        if case .failure(let error) = statusResult {
                            completion(false, "同步新建任务完成状态失败: \(error.localizedDescription)")
                            return
                        }
                        completion(true, nil)
                    }
                } else {
                    completion(true, nil)
                }
            case .failure(let error):
                completion(false, "从 Apple 新建飞书任务失败: \(error.localizedDescription)")
            }
        }
    }
}
