import Foundation
import EventKit

class EventKitManager: ObservableObject {
    static let shared = EventKitManager()

    let store = EKEventStore()
    @Published var isAuthorized = false

    private init() {
        checkAuthorizationStatus()
    }

    func checkAuthorizationStatus() {
        let status: EKAuthorizationStatus
        if #available(macOS 14.0, *) {
            status = EKEventStore.authorizationStatus(for: .reminder)
        } else {
            status = EKEventStore.authorizationStatus(for: .reminder)
        }

        DispatchQueue.main.async {
            // 在 macOS 14+ 中，.fullAccess 和 .authorized 都算作已授权
            if #available(macOS 14.0, *) {
                self.isAuthorized = (status == .fullAccess || status == .authorized)
            } else {
                self.isAuthorized = (status == .authorized)
            }
        }
    }

    func requestAccess(completion: @escaping (Bool) -> Void) {
        if #available(macOS 14.0, *) {
            store.requestFullAccessToReminders { granted, error in
                DispatchQueue.main.async {
                    self.isAuthorized = granted
                    completion(granted)
                }
                if let error = error {
                    print("请求提醒事项权限失败: \(error.localizedDescription)")
                }
            }
        } else {
            // Fallback on earlier versions
            store.requestAccess(to: .reminder) { granted, error in
                DispatchQueue.main.async {
                    self.isAuthorized = granted
                    completion(granted)
                }
                if let error = error {
                    print("请求提醒事项权限失败: \(error.localizedDescription)")
                }
            }
        }
    }

    // 获取默认的提醒事项列表
    func getDefaultList() -> EKCalendar? {
        return store.defaultCalendarForNewReminders()
    }

    // 获取或创建指定的列表 (Calendar)
    func getOrCreateCalendar(title: String) -> EKCalendar? {
        guard isAuthorized else { return nil }

        // 1. 查找是否已经存在同名列表
        let calendars = store.calendars(for: .reminder)
        if let existing = calendars.first(where: { $0.title == title }) {
            return existing
        }

        // 2. 如果不存在，则创建一个新的
        let newCalendar = EKCalendar(for: .reminder, eventStore: store)
        newCalendar.title = title

        // 必须指定一个 source（比如 iCloud 或 本地）
        if let defaultCalendar = store.defaultCalendarForNewReminders() {
            newCalendar.source = defaultCalendar.source
        } else {
            newCalendar.source = store.sources.first(where: { $0.sourceType == .local || $0.sourceType == .calDAV })
        }

        do {
            try store.saveCalendar(newCalendar, commit: true)
            print("📁 创建了新的提醒事项列表: \(title)")
            return newCalendar
        } catch {
            print("创建列表失败: \(error.localizedDescription)")
            return nil
        }
    }

    // 根据 ID 获取提醒事项
    func getReminder(byId id: String, completion: @escaping (EKReminder?) -> Void) {
        guard isAuthorized else {
            completion(nil)
            return
        }

        // EventKit 获取单个 Reminder 比较特殊，需要用 predicate
        let predicate = store.predicateForReminders(in: nil)
        store.fetchReminders(matching: predicate) { reminders in
            let found = reminders?.first(where: { $0.calendarItemIdentifier == id })
            completion(found)
        }
    }

    // 保存提醒事项
    @discardableResult
    func saveReminder(_ reminder: EKReminder) -> Bool {
        do {
            try store.save(reminder, commit: true)
            return true
        } catch {
            print("保存提醒事项失败: \(error.localizedDescription)")
            return false
        }
    }

    // 创建一个简单的提醒事项用于测试
    func createTestReminder(title: String) {
        guard isAuthorized, let calendar = getDefaultList() else {
            print("未授权或找不到默认列表")
            return
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = calendar

        do {
            try store.save(reminder, commit: true)
            print("成功创建测试提醒事项: \(title)")
        } catch {
            print("保存提醒事项失败: \(error.localizedDescription)")
        }
    }
}