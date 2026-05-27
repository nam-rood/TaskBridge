import Foundation
import EventKit

let store = EKEventStore()
let sem = DispatchSemaphore(value: 0)

func printCalendars() {
    let calendars = store.calendars(for: .reminder)
    for calendar in calendars {
        if calendar.title.hasPrefix("飞书") {
            print("列表: \(calendar.title)")
        }
    }
    sem.signal()
}

if #available(macOS 14.0, *) {
    store.requestFullAccessToReminders { granted, error in
        if granted { printCalendars() } else { sem.signal() }
    }
} else {
    store.requestAccess(to: .reminder) { granted, error in
        if granted { printCalendars() } else { sem.signal() }
    }
}
sem.wait()
