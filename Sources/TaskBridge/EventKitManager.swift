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

        let authorized: Bool
        if #available(macOS 14.0, *) {
            authorized = (status == .fullAccess || status == .authorized)
        } else {
            authorized = (status == .authorized)
        }

        if Thread.isMainThread {
            isAuthorized = authorized
        } else {
            DispatchQueue.main.async {
                self.isAuthorized = authorized
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

    func getCalendar(byId id: String) -> EKCalendar? {
        store.calendar(withIdentifier: id)
    }

    func getCalendar(title: String) -> EKCalendar? {
        store.calendars(for: .reminder).first { $0.title == title }
    }

    func fetchReminders(in calendars: [EKCalendar], completion: @escaping ([EKReminder]) -> Void) {
        guard isAuthorized else {
            completion([])
            return
        }

        let predicate = store.predicateForReminders(in: calendars)
        store.fetchReminders(matching: predicate) { reminders in
            DispatchQueue.main.async {
                completion(reminders ?? [])
            }
        }
    }

    func dueInfo(from reminder: EKReminder) -> (timestamp: String, isAllDay: Bool)? {
        guard let components = reminder.dueDateComponents,
              let date = Calendar.current.date(from: components) else {
            return nil
        }

        let timestamp = String(Int64(date.timeIntervalSince1970 * 1000))
        let isAllDay = components.hour == nil && components.minute == nil && components.second == nil
        return (timestamp, isAllDay)
    }

    func applyDue(timestamp: String?, isAllDay: Bool, to reminder: EKReminder) {
        guard let timestamp = timestamp,
              let milliseconds = Double(timestamp),
              !timestamp.isEmpty else {
            reminder.dueDateComponents = nil
            return
        }

        let date = Date(timeIntervalSince1970: milliseconds / 1000)
        if isAllDay {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: date)
        } else {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        }
    }

    // 根据标题在指定日历中查找提醒事项
    func findReminder(title: String, in calendar: EKCalendar, completion: @escaping (EKReminder?) -> Void) {
        guard isAuthorized else {
            completion(nil)
            return
        }

        let predicate = store.predicateForReminders(in: [calendar])
        store.fetchReminders(matching: predicate) { reminders in
            let found = reminders?.first(where: { $0.title == title })
            completion(found)
        }
    }

    func getReminder(byId id: String, completion: @escaping (EKReminder?) -> Void) {
        guard isAuthorized else {
            completion(nil)
            return
        }

        if let reminder = store.calendarItem(withIdentifier: id) as? EKReminder {
            completion(reminder)
            return
        }

        let predicate = store.predicateForReminders(in: nil)
        store.fetchReminders(matching: predicate) { reminders in
            let reminder = reminders?.first { $0.calendarItemIdentifier == id }
            DispatchQueue.main.async {
                completion(reminder)
            }
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

    @discardableResult
    func removeReminder(_ reminder: EKReminder) -> Bool {
        do {
            try store.remove(reminder, commit: true)
            return true
        } catch {
            print("删除提醒事项失败: \(error.localizedDescription)")
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