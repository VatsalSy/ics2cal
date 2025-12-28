import Foundation

#if canImport(EventKit)
import EventKit

final class CalendarSync {
    let store: EKEventStore
    init(store: EKEventStore) { self.store = store }

    private static let iso8601: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return fmt
    }()

    func listCalendars() -> [EKCalendar] {
        store.calendars(for: .event)
    }

    func events(in cal: EKCalendar, from: Date, to: Date) -> [EKEvent] {
        let pred = store.predicateForEvents(withStart: from, end: to, calendars: [cal])
        return store.events(matching: pred)
    }

    func createEvent(from src: Event, in calendar: EKCalendar, sourceLabel: String?) throws -> EKEvent {
        let ek = EKEvent(eventStore: store)
        ek.calendar = calendar
        apply(src, to: ek, sourceLabel: sourceLabel)
        try store.save(ek, span: .thisEvent, commit: false)
        return ek
    }

    func updateEvent(_ ek: EKEvent, with src: Event, sourceLabel: String?) throws {
        apply(src, to: ek, sourceLabel: sourceLabel)
        try store.save(ek, span: .thisEvent, commit: false)
    }

    func removeEvent(_ ek: EKEvent) throws {
        try store.remove(ek, span: .thisEvent, commit: false)
    }

    func commitChanges() throws {
        try store.commit()
    }

    // MARK: - Private helpers
    private func apply(_ src: Event, to ek: EKEvent, sourceLabel: String?) {
        ek.title = src.title
        ek.startDate = src.startDate
        ek.endDate = src.endDate
        ek.isAllDay = src.isAllDay
        ek.location = src.location
        if let url = src.url {
            ek.url = url
        } else {
            ek.url = nil
        }

        var meta = MetadataNotes.decode(from: ek.notes) ?? Meta(v: 1, hash: src.fingerprint, sources: [], uids: [], seen: [:])
        meta.hash = src.fingerprint
        if let uid = src.uid, !meta.uids.contains(uid) { meta.uids.append(uid) }
        if let s = sourceLabel {
            if !meta.sources.contains(s) { meta.sources.append(s) }
            meta.seen[s] = Self.iso8601.string(from: Date())
        }
        ek.notes = MetadataNotes.encode(meta: meta, into: ek.notes)
    }
}

#endif
