import Foundation
import EventKit

let store = EKEventStore()
let sem = DispatchSemaphore(value: 0)

func printTasks() {
    let calendars = store.calendars(for: .reminder).filter { $0.title == "飞书 - 独立任务" }
    let predicate = store.predicateForReminders(in: calendars)
    store.fetchReminders(matching: predicate) { reminders in
        if let reminders = reminders {
            print("任务数量: \(reminders.count)")
            for r in reminders {
                print("- \(r.title ?? "")")
            }
        }
        sem.signal()
    }
}

if #available(macOS 14.0, *) {
    store.requestFullAccessToReminders { granted, error in
        if granted { printTasks() } else { sem.signal() }
    }
} else {
    store.requestAccess(to: .reminder) { granted, error in
        if granted { printTasks() } else { sem.signal() }
    }
}
sem.wait()
