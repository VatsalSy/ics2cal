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
        ics2cal — Sync ICS files to Apple Calendar (no external deps)

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

        // For scaffold: only compute and display a plan. Actual write paths can be added incrementally.
        let plan = SyncPlanner.plan(events: events, source: source, mirror: mirror, adopt: adopt, timeWindowMin: timeWindowMin, store: store, calendar: target, from: from, to: to)
        print(plan.summary())
        if !dryRun && !addOnly {
            // Placeholder for write execution. Intentionally not implemented in scaffold.
            print("(scaffold) Apply plan: not yet implemented.")
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

// MARK: - SyncPlanner (scaffold)
struct SyncPlanner {
    #if canImport(EventKit)
    struct Plan {
        let toAdd: [Event]
        let toUpdate: [Event]
        let toDelete: [EKEvent]
        func summary() -> String {
            "Plan: add=\(toAdd.count), update=\(toUpdate.count), delete=\(toDelete.count)"
        }
    }

    static func plan(events: [Event], source: String?, mirror: Bool, adopt: Bool, timeWindowMin: Int, store: EKEventStore, calendar: EKCalendar, from: Date, to: Date) -> Plan {
        // Minimal scaffold: no real matching yet. Pretend everything would be added.
        return Plan(toAdd: events, toUpdate: [], toDelete: [])
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

