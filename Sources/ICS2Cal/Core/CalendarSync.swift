import Foundation

#if canImport(EventKit)
import EventKit

final class CalendarSync {
    let store: EKEventStore
    init(store: EKEventStore) { self.store = store }

    func listCalendars() -> [EKCalendar] {
        store.calendars(for: .event)
    }

    func events(in cal: EKCalendar, from: Date, to: Date) -> [EKEvent] {
        let pred = store.predicateForEvents(withStart: from, end: to, calendars: [cal])
        return store.events(matching: pred)
    }
}

#endif

