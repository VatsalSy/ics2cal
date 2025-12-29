import Foundation

#if canImport(EventKit)
import EventKit
#endif

enum CLIError: Error, CustomStringConvertible {
    case usage(String)
    case io(String)
    case parse(String)

    var description: String {
        switch self {
        case .usage(let m): return m
        case .io(let m): return m
        case .parse(let m): return m
        }
    }
}

struct CLI {
    static func run() throws {
        var args = CommandLine.arguments.dropFirst()
        guard let cmd = args.first else {
            printUsage()
            return
        }
        args = args.dropFirst()

        switch cmd {
        case "help", "-h", "--help":
            printUsage()
        case "info":
            try cmdInfo(args: Array(args))
        case "list":
            try cmdList(args: Array(args))
        case "sync":
            let dryRun = args.contains("--dry-run")
            try cmdSync(args: Array(args), dryRun: dryRun)
        case "dry-run":
            try cmdSync(args: Array(args), dryRun: true)
        default:
            throw CLIError.usage("Unknown command: \(cmd)\n\n\(usageText)")
        }
    }

    private static func printUsage() {
        print(usageText)
    }

    private static var usageText: String {
        """
        ics2cal — Sync ICS files to Apple Calendar

        Usage:
          ics2cal info <ics-file>
          ics2cal list
          ics2cal sync <ics-file> --calendar <name> [options]
          ics2cal dry-run <ics-file> --calendar <name> [options]

        Commands:
          info        Parse an .ics file and print a summary of the contained events.
          list        List available calendars.
          sync        Synchronize events from an .ics file into the given calendar.
          dry-run     Same as 'sync' but only reports changes without modifying calendars.

        Options (sync):
          --calendar <name>       Target calendar name to sync into (required).
          --source <id>           Restrict to a specific calendar source identifier.
          --mirror                Remove events from the calendar that are no longer in the .ics file.
          --adopt-existing        Match and adopt existing events that correspond to the .ics entries.
          --time-window <min>     Only sync events within the next <min> minutes.
          --from YYYY-MM-DD       Only sync events starting on or after this date.
          --to YYYY-MM-DD         Only sync events ending on or before this date.
          --add-only              Only add new events; do not update or delete existing ones.
          --dry-run               Show what would change without performing any modifications.

        """
    }

    // MARK: - Authorization Helper
    #if canImport(EventKit)
    /// Request EventKit authorization and return whether access was granted.
    /// Uses new APIs on macOS 14+/iOS 17+, falls back to old APIs on older versions.
    private static func requestEventAccess(store: EKEventStore) -> Bool {
        var status = EKEventStore.authorizationStatus(for: .event)

        if status == .notDetermined {
            let sem = DispatchSemaphore(value: 0)

            if #available(macOS 14.0, iOS 17.0, *) {
                store.requestFullAccessToEvents { _, _ in sem.signal() }
            } else {
                store.requestAccess(to: .event) { _, _ in sem.signal() }
            }

            sem.wait()
            status = EKEventStore.authorizationStatus(for: .event)
        }

        // Check authorization status using appropriate API
        if #available(macOS 14.0, iOS 17.0, *) {
            return status == .fullAccess || status == .writeOnly
        } else {
            return status == .authorized
        }
    }
    #endif

    // MARK: info
    static func cmdInfo(args: [String]) throws {
        guard let icsPath = args.first else { throw CLIError.usage("info requires <ics-file>") }
        let url = URL(fileURLWithPath: icsPath)
        let parser = ICSParser()
        let events = try parser.parse(fileURL: url)
        print("Found \(events.count) event(s)")
        let iso = ISO8601DateFormatter()
        for (i, e) in events.enumerated() {
            print("\(i+1). \(e.title) — \(iso.string(from: e.startDate)) → \(iso.string(from: e.endDate)) [hash=\(e.fingerprint)]")
        }
    }

    // MARK: list
    static func cmdList(args: [String]) throws {
        #if canImport(EventKit)
        let store = EKEventStore()
        guard requestEventAccess(store: store) else {
            print("Calendar access not authorized.")
            return
        }
        let cals = store.calendars(for: .event)
        for c in cals { print(c.title) }
        #else
        print("EventKit not available in this environment.")
        #endif
    }

    // MARK: sync / dry-run
    static func cmdSync(args: [String], dryRun: Bool) throws {
        var file: String?; var calendar: String?; var source: String?; var mirror = false
        var adopt = false; var timeWindowMin = 5; var fromDate: Date?; var toDate: Date?; var addOnly = false

        var it = args.makeIterator()
        func next() -> String? { it.next() }
        while let a = next() {
            switch a {
            case "--calendar", "-c": calendar = next()
            case "--source", "-S": source = next()
            case "--mirror": mirror = true
            case "--adopt-existing": adopt = true
            case "--time-window": if let v = next(), let n = Int(v) { timeWindowMin = n }
            case "--from": if let v = next() { fromDate = DateParser.dateOnly(v) }
            case "--to": if let v = next() { toDate = DateParser.dateOnly(v) }
            case "--add-only": addOnly = true
            case "--dry-run": /* accepted for symmetry */ break
            default:
                if file == nil { file = a } else { throw CLIError.usage("Unexpected arg: \(a)") }
            }
        }
        guard let file else { throw CLIError.usage("sync requires <ics-file>") }
        guard let calendar else { throw CLIError.usage("--calendar is required") }
        if mirror && source == nil { throw CLIError.usage("--mirror requires --source <id>") }

        let url = URL(fileURLWithPath: file)
        let parser = ICSParser()
        let events = try parser.parse(fileURL: url)
        // Compute window if not provided
        let minDate = events.map { $0.startDate }.min() ?? Date()
        let maxDate = events.map { $0.endDate }.max() ?? Date()
        let defaultFrom = Calendar.current.date(byAdding: .day, value: -30, to: minDate) ?? minDate
        let defaultTo = Calendar.current.date(byAdding: .day, value: 365, to: maxDate) ?? maxDate
        let from = fromDate ?? defaultFrom
        let to = toDate ?? defaultTo

        #if canImport(EventKit)
        let store = EKEventStore()
        guard requestEventAccess(store: store) else {
            print("Calendar access not authorized. Run ics2cal list to grant.")
            return
        }

        guard let target = store.calendars(for: .event).first(where: { $0.title == calendar }) else {
            print("Calendar not found: \(calendar)")
            return
        }

        let plan = SyncPlanner.plan(events: events, source: source, mirror: mirror, adopt: adopt, timeWindowMin: timeWindowMin, addOnly: addOnly, store: store, calendar: target, from: from, to: to)
        print(plan.summary())
        if !dryRun {
            let sync = CalendarSync(store: store)
            for add in plan.toAdd {
                do { _ = try sync.createEvent(from: add.event, in: target, sourceLabel: source) }
                catch { fputs("Add failed: \(error)\n", stderr) }
            }
            for upd in plan.toUpdate {
                if let ek = upd.existing {
                    do { try sync.updateEvent(ek, with: upd.new, sourceLabel: source) }
                    catch { fputs("Update (\(upd.reason)) failed: \(error)\n", stderr) }
                }
            }
            for del in plan.toDelete {
                switch del.action {
                case .delete:
                    do { try sync.removeEvent(del.existing) }
                    catch { fputs("Delete failed: \(error)\n", stderr) }
                case .removeSourceOnly(let newMeta):
                    del.existing.notes = MetadataNotes.encode(meta: newMeta, into: del.existing.notes)
                    do {
                        try store.save(del.existing, span: .thisEvent, commit: false)
                    } catch {
                        fputs("Detach source failed: \(error)\n", stderr)
                    }
                }
            }
            do { try sync.commitChanges() }
            catch { fputs("Commit failed: \(error)\n", stderr) }
        }
        #else
        print("EventKit not available. Parsed \(events.count) event(s). This is a dry scaffold.")
        #endif
    }
}

// MARK: - DateParser
enum DateParser {
    private static let dateOnlyFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt
    }()

    static func dateOnly(_ s: String) -> Date? {
        dateOnlyFormatter.date(from: s)
    }
}

// MARK: - SyncPlanner
struct SyncPlanner {
    #if canImport(EventKit)
    struct AddItem { let event: Event }
    struct UpdateItem { let existing: EKEvent?; let new: Event; let reason: String }
    enum DeleteAction { case delete, removeSourceOnly(Meta) }
    struct DeleteItem { let existing: EKEvent; let action: DeleteAction; let reason: String }

    struct Plan {
        var toAdd: [AddItem]
        var toUpdate: [UpdateItem]
        var toDelete: [DeleteItem]
        func summary() -> String {
            "Plan: add=\(toAdd.count), update=\(toUpdate.count), delete=\(toDelete.count)"
        }
    }

    static func plan(events: [Event], source: String?, mirror: Bool, adopt: Bool, timeWindowMin: Int, addOnly: Bool, store: EKEventStore, calendar: EKCalendar, from: Date, to: Date) -> Plan {
        let sync = CalendarSync(store: store)
        let widen = TimeInterval(timeWindowMin * 60)
        let existing = sync.events(in: calendar, from: from.addingTimeInterval(-widen), to: to.addingTimeInterval(widen))

        var byHash: [String: EKEvent] = [:]
        var byUID: [String: EKEvent] = [:]
        var allExisting: [EKEvent] = []
        for e in existing {
            allExisting.append(e)
            if let meta = MetadataNotes.decode(from: e.notes) {
                if byHash[meta.hash] != nil {
                    fputs("Warning: multiple events share metadata hash '\(meta.hash)'; some events may be skipped during matching.\n", stderr)
                }
                byHash[meta.hash] = e
                for u in meta.uids {
                    if byUID[u] != nil {
                        fputs("Warning: multiple events share metadata UID '\(u)'; some events may be skipped during matching.\n", stderr)
                    }
                    byUID[u] = e
                }
            }
        }

        var usedExisting = Set<String>()
        var adds: [AddItem] = []
        var updates: [UpdateItem] = []

        func norm(_ s: String?) -> String { TextNormalize.norm(s ?? "") }

        for ev in events {
            // 1) UID precedence
            if let uid = ev.uid, let match = byUID[uid], let id = match.eventIdentifier {
                usedExisting.insert(id)
                let needsUpdate = (match.title != ev.title)
                    || (match.location ?? "") != (ev.location ?? "")
                    || abs(match.startDate.timeIntervalSince(ev.startDate)) > 1
                    || abs(match.endDate.timeIntervalSince(ev.endDate)) > 1
                    || match.isAllDay != ev.isAllDay
                var needsMeta = false
                if let src = source, let meta = MetadataNotes.decode(from: match.notes) { needsMeta = !meta.sources.contains(src) }
                if !addOnly && (needsUpdate || needsMeta) {
                    updates.append(UpdateItem(existing: match, new: ev, reason: needsUpdate ? "uid-match" : "attach-source"))
                }
                continue
            }

            // 2) Hash match
            let legacyFingerprint = Fingerprint.legacyEventHash(title: ev.title, location: ev.location, start: ev.startDate, end: ev.endDate)
            if let match = byHash[ev.fingerprint] ?? byHash[legacyFingerprint], let id = match.eventIdentifier {
                usedExisting.insert(id)
                let needsUpdate = (match.title != ev.title)
                    || (match.location ?? "") != (ev.location ?? "")
                    || abs(match.startDate.timeIntervalSince(ev.startDate)) > 1
                    || abs(match.endDate.timeIntervalSince(ev.endDate)) > 1
                    || match.isAllDay != ev.isAllDay
                var needsMeta = false
                if let src = source, let meta = MetadataNotes.decode(from: match.notes) { needsMeta = !meta.sources.contains(src) }
                if !addOnly && (needsUpdate || needsMeta) {
                    updates.append(UpdateItem(existing: match, new: ev, reason: needsUpdate ? "hash-match" : "attach-source"))
                }
                continue
            }

            if adopt {
                let candidates = allExisting.filter { event in
                    guard let id = event.eventIdentifier else { return false }
                    return !usedExisting.contains(id)
                }
                let evTitle = norm(ev.title)
                let evLoc = norm(ev.location)
                var adopted: EKEvent?
                for cand in candidates {
                    let titleMatch = norm(cand.title) == evTitle
                    let locMatch = norm(cand.location) == evLoc || evLoc.isEmpty || norm(cand.location).isEmpty
                    let startDelta = abs(cand.startDate.timeIntervalSince(ev.startDate))
                    let candDuration = cand.endDate.timeIntervalSince(cand.startDate)
                    let evDuration = ev.endDate.timeIntervalSince(ev.startDate)
                    let durDelta = abs(candDuration - evDuration)
                    let allDayMatch = cand.isAllDay == ev.isAllDay
                    if titleMatch && locMatch && startDelta <= widen && durDelta <= widen && allDayMatch {
                        adopted = cand
                        break
                    }
                }
                if let adopted {
                    if let id = adopted.eventIdentifier { usedExisting.insert(id) }
                    if !addOnly {
                        updates.append(UpdateItem(existing: adopted, new: ev, reason: "adopt"))
                    }
                    continue
                }
            }

            adds.append(AddItem(event: ev))
        }

        var deletes: [DeleteItem] = []
        if mirror, let source = source {
            var incomingHashes = Set<String>()
            for ev in events {
                incomingHashes.insert(ev.fingerprint)
                incomingHashes.insert(Fingerprint.legacyEventHash(title: ev.title, location: ev.location, start: ev.startDate, end: ev.endDate))
            }
            for e in allExisting {
                guard let id = e.eventIdentifier else { continue }
                if usedExisting.contains(id) { continue }
                guard let meta = MetadataNotes.decode(from: e.notes) else { continue }
                guard meta.sources.contains(source) else { continue }
                if !incomingHashes.contains(meta.hash) {
                    var newMeta = meta
                    newMeta.sources.removeAll { $0 == source }
                    if newMeta.sources.isEmpty {
                        if !addOnly { deletes.append(DeleteItem(existing: e, action: .delete, reason: "mirror: not in source anymore")) }
                    } else {
                        if !addOnly { deletes.append(DeleteItem(existing: e, action: .removeSourceOnly(newMeta), reason: "mirror: detach source")) }
                    }
                }
            }
        }

        return Plan(toAdd: adds, toUpdate: updates, toDelete: deletes)
    }
    #endif
}

// Entrypoint
do {
    try CLI.run()
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(2)
}
