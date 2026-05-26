import Foundation
import EventKit

let store = EKEventStore()
let sem = DispatchSemaphore(value: 0)

func clearCalendars() {
    let calendars = store.calendars(for: .reminder)
    var deletedCount = 0
    for calendar in calendars {
        if calendar.title.hasPrefix("飞书 - ") {
            do {
                try store.removeCalendar(calendar, commit: true)
                print("✅ 删除了列表: \(calendar.title)")
                deletedCount += 1
            } catch {
                print("❌ 删除列表 \(calendar.title) 失败: \(error)")
            }
        }
    }
    print("🎉 清理完成，共删除了 \(deletedCount) 个飞书相关的列表。")
    sem.signal()
}

if #available(macOS 14.0, *) {
    store.requestFullAccessToReminders { granted, error in
        if granted {
            clearCalendars()
        } else {
            print("❌ 未获得提醒事项权限")
            sem.signal()
        }
    }
} else {
    store.requestAccess(to: .reminder) { granted, error in
        if granted {
            clearCalendars()
        } else {
            print("❌ 未获得提醒事项权限")
            sem.signal()
        }
    }
}

sem.wait()
