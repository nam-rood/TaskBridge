import Foundation
import EventKit

class SyncEngine {
    static let shared = SyncEngine()

    private let feishuAPI = FeishuAPIClient.shared
    private let dbManager = DatabaseManager.shared
    private let eventKitManager = EventKitManager.shared

    private var isSyncing = false

    private init() {}

    /// 执行单向同步：飞书 -> Apple Reminders
    func syncFeishuToApple(completion: @escaping (Bool, String) -> Void) {
        guard !isSyncing else {
            completion(false, "同步正在进行中，请稍后再试")
            return
        }

        guard eventKitManager.isAuthorized else {
            completion(false, "未获取提醒事项权限")
            return
        }

        isSyncing = true
        print("🔄 开始同步：飞书 -> Apple Reminders")

        var totalSuccess = 0
        var totalUpdate = 0
        let group = DispatchGroup()

        // 1. 先全局拉取所有任务，这样能保留 tasklists 字段
        group.enter()
        feishuAPI.fetchTasks(tasklistGuid: nil) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let allTasks):
                print("📝 全局获取到 \(allTasks.count) 个任务")

                // 2. 获取所有清单和分组信息
                self.feishuAPI.fetchTasklists { listResult in
                    switch listResult {
                    case .success(let tasklists):
                        print("📁 获取到 \(tasklists.count) 个飞书清单")

                        // 遍历清单，获取分组并分配任务
                        for tasklist in tasklists {
                            group.enter()
                            self.feishuAPI.fetchSections(tasklistGuid: tasklist.guid) { sectionResult in
                                switch sectionResult {
                                case .success(let sections):
                                    if sections.isEmpty {
                                        // 清单没有分组
                                        let listTasks = allTasks.filter { task in
                                            task.tasklists?.contains(where: { $0.tasklistGuid == tasklist.guid }) ?? false
                                        }
                                        self.syncSection(tasklist: tasklist, section: nil, tasks: listTasks) { s, u in
                                            totalSuccess += s
                                            totalUpdate += u
                                            group.leave()
                                        }
                                    } else {
                                        // 清单有分组
                                        let sectionGroup = DispatchGroup()
                                        var secSuccess = 0
                                        var secUpdate = 0

                                        for section in sections {
                                            sectionGroup.enter()
                                            let secTasks = allTasks.filter { task in
                                                task.tasklists?.contains(where: { $0.tasklistGuid == tasklist.guid && $0.sectionGuid == section.guid }) ?? false
                                            }
                                            self.syncSection(tasklist: tasklist, section: section, tasks: secTasks) { s, u in
                                                secSuccess += s
                                                secUpdate += u
                                                sectionGroup.leave()
                                            }
                                        }

                                        sectionGroup.notify(queue: .main) {
                                            totalSuccess += secSuccess
                                            totalUpdate += secUpdate
                                            group.leave()
                                        }
                                    }
                                case .failure(let error):
                                    print("❌ 获取清单 [\(tasklist.name)] 的分组失败: \(error.localizedDescription)")
                                    group.leave()
                                }
                            }
                        }

                        // 3. 处理独立任务（不属于任何清单的任务）
                        let independentTasks = allTasks.filter { task in
                            return task.tasklists == nil || task.tasklists!.isEmpty
                        }

                        if !independentTasks.isEmpty {
                            print("📝 发现 \(independentTasks.count) 个独立任务")
                            if let defaultCalendar = self.eventKitManager.getOrCreateCalendar(title: "飞书 - 独立任务") {
                                group.enter()
                                self.processFeishuTasks(independentTasks, in: defaultCalendar) { s, u in
                                    totalSuccess += s
                                    totalUpdate += u
                                    group.leave()
                                }
                            }
                        }

                    case .failure(let error):
                        print("❌ 获取飞书清单失败: \(error.localizedDescription)")
                    }
                    group.leave()
                }

            case .failure(let error):
                print("❌ 全局获取任务失败: \(error.localizedDescription)")
                group.leave()
            }
        }

        group.notify(queue: .main) {
            self.isSyncing = false
            let msg = "同步完成！新建: \(totalSuccess), 更新: \(totalUpdate)"
            print("✅ \(msg)")
            completion(true, msg)
        }
    }

    private func syncSection(tasklist: FeishuTasklist, section: FeishuSection?, tasks: [FeishuTask], completion: @escaping (Int, Int) -> Void) {
        // 1. 拼接 Apple 列表名称
        let calendarName: String
        let sectionId: String
        if let sec = section {
            calendarName = "飞书 - \(tasklist.name) - \(sec.name)"
            sectionId = sec.guid
        } else {
            calendarName = "飞书 - \(tasklist.name)"
            sectionId = ""
        }

        // 2. 在 Mac 上获取或创建同名的列表
        guard let calendar = eventKitManager.getOrCreateCalendar(title: calendarName) else {
            completion(0, 0)
            return
        }

        // 3. 记录映射
        dbManager.saveListMapping(feishuListId: tasklist.guid, feishuSectionId: sectionId, appleId: calendar.calendarIdentifier)

        // 4. 处理传入的任务
        self.processFeishuTasks(tasks, in: calendar) { success, update in
            completion(success, update)
        }
    }

    private func processFeishuTasks(_ tasks: [FeishuTask], in calendar: EKCalendar, completion: @escaping (Int, Int) -> Void) {
        var successCount = 0
        var updateCount = 0
        let group = DispatchGroup()

        for task in tasks {
            group.enter()

            if let mapping = dbManager.getMapping(byFeishuId: task.guid) {
                eventKitManager.getReminder(byId: mapping.appleReminderId) { reminder in
                    if let reminder = reminder {
                        var needsUpdate = false
                        if reminder.title != task.summary {
                            reminder.title = task.summary
                            needsUpdate = true
                        }
                        let isCompletedInFeishu = (task.completedAt != nil && task.completedAt != "0")
                        if reminder.isCompleted != isCompletedInFeishu {
                            reminder.isCompleted = isCompletedInFeishu
                            needsUpdate = true
                        }
                        if needsUpdate {
                            self.eventKitManager.saveReminder(reminder)
                            updateCount += 1
                        }
                    } else {
                        self.createNewReminder(for: task, in: calendar)
                        successCount += 1
                    }
                    group.leave()
                }
            } else {
                createNewReminder(for: task, in: calendar)
                successCount += 1
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(successCount, updateCount)
        }
    }

    private func createNewReminder(for task: FeishuTask, in calendar: EKCalendar) {
        let reminder = EKReminder(eventStore: eventKitManager.store)
        reminder.title = task.summary
        reminder.calendar = calendar

        if task.completedAt != nil && task.completedAt != "0" {
            reminder.isCompleted = true
        }

        if eventKitManager.saveReminder(reminder) {
            // 保存映射到数据库
            dbManager.saveMapping(feishuId: task.guid, appleId: reminder.calendarItemIdentifier)
            print("✨ 新建提醒事项: \(task.summary)")
        }
    }
}