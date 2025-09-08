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
            try cmdSync(args: Array(args), dryRun: false)
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
          ics2cal info <ics-file> [--format summary|detailed|json]
          ics2cal list [--format names|json]
          ics2cal sync <ics-file> --calendar <name> [--source <id>] [--mirror] [--adopt-existing] [--time-window <min>] [--from YYYY-MM-DD] [--to YYYY-MM-DD] [--add-only] [--dry-run]

        """
    }

    // MARK: info
    static func cmdInfo(args: [String]) throws {
        guard let icsPath = args.first else { throw CLIError.usage("info requires <ics-file>") }
        let url = URL(fileURLWithPath: icsPath)
        let parser = ICSParser()
        let events = try parser.parse(fileURL: url)
        print("Found \(events.count) event(s)")
        for (i, e) in events.enumerated() {
            print("\(i+1). \(e.title) — \(ISO8601DateFormatter().string(from: e.startDate)) → \(ISO8601DateFormatter().string(from: e.endDate)) [hash=\(e.fingerprint)]")
        }
    }

    // MARK: list
    static func cmdList(args: [String]) throws {
        #if canImport(EventKit)
        let store = EKEventStore()
        var status = EKEventStore.authorizationStatus(for: .event)
        if status == .notDetermined {
            let sem = DispatchSemaphore(value: 0)
            store.requestAccess(to: .event) { _, _ in sem.signal() }
            sem.wait()
            status = EKEventStore.authorizationStatus(for: .event)
        }
        guard status == .authorized else {
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
        let defaultFrom = Calendar.current.date(byAdding: .day, value: -30, to: minDate)!
        let defaultTo = Calendar.current.date(byAdding: .day, value: 365, to: maxDate)!
        let from = fromDate ?? defaultFrom
        let to = toDate ?? defaultTo

        #if canImport(EventKit)
        let store = EKEventStore()
        var status = EKEventStore.authorizationStatus(for: .event)
        if status == .notDetermined {
            let sem = DispatchSemaphore(value: 0)
            store.requestAccess(to: .event) { _, _ in sem.signal() }
            sem.wait()
            status = EKEventStore.authorizationStatus(for: .event)
        }
        guard status == .authorized else {
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
                _ = try? sync.createEvent(from: add.event, in: target, sourceLabel: source)
            }
            for upd in plan.toUpdate {
                if let ek = upd.existing {
                    try? sync.updateEvent(ek, with: upd.new, sourceLabel: source)
                }
            }
            for del in plan.toDelete {
                switch del.action {
                case .delete:
                    try? sync.removeEvent(del.existing)
                case .removeSourceOnly(let newMeta):
                    del.existing.notes = MetadataNotes.encode(meta: newMeta, into: del.existing.notes)
                    try? store.save(del.existing, span: .thisEvent, commit: true)
                }
            }
        }
        #else
        print("EventKit not available. Parsed \(events.count) event(s). This is a dry scaffold.")
        #endif
    }
}

// MARK: - DateParser
enum DateParser {
    static func dateOnly(_ s: String) -> Date? {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.date(from: s)
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
                byHash[meta.hash] = e
                for u in meta.uids { byUID[u] = e }
            }
        }

        var usedExisting = Set<String>()
        var adds: [AddItem] = []
        var updates: [UpdateItem] = []

        func norm(_ s: String?) -> String { TextNormalize.norm(s ?? "") }

        for ev in events {
            // 1) UID precedence
            if let uid = ev.uid, let match = byUID[uid] {
                usedExisting.insert(match.eventIdentifier)
                let needsUpdate = (match.title != ev.title) || (match.location ?? "") != (ev.location ?? "") || abs(match.startDate.timeIntervalSince(ev.startDate)) > 1 || abs(match.endDate.timeIntervalSince(ev.endDate)) > 1
                var needsMeta = false
                if let src = source, let meta = MetadataNotes.decode(from: match.notes) { needsMeta = !meta.sources.contains(src) }
                if !addOnly && (needsUpdate || needsMeta) {
                    updates.append(UpdateItem(existing: match, new: ev, reason: needsUpdate ? "uid-match" : "attach-source"))
                }
                continue
            }

            // 2) Hash match
            if let match = byHash[ev.fingerprint] {
                usedExisting.insert(match.eventIdentifier)
                let needsUpdate = (match.title != ev.title) || (match.location ?? "") != (ev.location ?? "") || abs(match.startDate.timeIntervalSince(ev.startDate)) > 1 || abs(match.endDate.timeIntervalSince(ev.endDate)) > 1
                var needsMeta = false
                if let src = source, let meta = MetadataNotes.decode(from: match.notes) { needsMeta = !meta.sources.contains(src) }
                if !addOnly && (needsUpdate || needsMeta) {
                    updates.append(UpdateItem(existing: match, new: ev, reason: needsUpdate ? "hash-match" : "attach-source"))
                }
                continue
            }

            if adopt {
                let candidates = allExisting.filter { !usedExisting.contains($0.eventIdentifier) }
                let evTitle = norm(ev.title)
                let evLoc = norm(ev.location)
                var adopted: EKEvent? = nil
                for cand in candidates {
                    let titleMatch = norm(cand.title) == evTitle
                    let locMatch = norm(cand.location) == evLoc || evLoc.isEmpty || norm(cand.location).isEmpty
                    let startDelta = abs(cand.startDate.timeIntervalSince(ev.startDate))
                    let durDelta = abs(cand.endDate.timeIntervalSince(ev.endDate))
                    if titleMatch && locMatch && startDelta <= widen && durDelta <= widen {
                        adopted = cand
                        break
                    }
                }
                if let adopted {
                    usedExisting.insert(adopted.eventIdentifier)
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
            let incomingHashes = Set(events.map { $0.fingerprint })
            for e in allExisting {
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
