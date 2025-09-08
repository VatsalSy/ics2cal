import Foundation

final class ICSParser {
    func parse(fileURL: URL) throws -> [Event] {
        let data = try Data(contentsOf: fileURL)
        guard let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw NSError(domain: "ICS", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to decode file contents"])
        }
        let lines = unfoldLines(content)
        var events: [Event] = []
        var buf: [String] = []
        var inEvent = false
        for line in lines {
            if line == "BEGIN:VEVENT" { inEvent = true; buf = []; continue }
            if line == "END:VEVENT" { inEvent = false; if let e = try? parseVEvent(buf) { events.append(e) }; buf = []; continue }
            if inEvent { buf.append(line) }
        }
        return events
    }

    func parseVEvent(_ lines: [String]) throws -> Event {
        var uid: String?
        var summary: String?
        var description: String?
        var location: String?
        var url: URL?
        var organizer: String?
        var status: EventStatus = .confirmed
        var created: Date?
        var lastModified: Date?
        var sequence = 0
        var dtStart: (String, String?)?
        var dtEnd: (String, String?)?

        for raw in lines {
            let (name, params, value) = splitProperty(raw)
            switch name {
            case "UID": uid = value
            case "SUMMARY": summary = value
            case "DESCRIPTION": description = value
            case "LOCATION": location = value
            case "URL": url = URL(string: value)
            case "ORGANIZER": organizer = value
            case "STATUS": status = EventStatus(rawValue: value.uppercased()) ?? status
            case "CREATED": created = parseDateTime(value, tzid: params["TZID"])
            case "LAST-MODIFIED": lastModified = parseDateTime(value, tzid: params["TZID"])
            case "SEQUENCE": sequence = Int(value) ?? sequence
            case "DTSTART": dtStart = (value, params["TZID"]) 
            case "DTEND": dtEnd = (value, params["TZID"]) 
            default: continue
            }
        }

        guard let s = summary else { throw NSError(domain: "ICS", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing SUMMARY"]) }
        guard let dtStartRaw = dtStart else { throw NSError(domain: "ICS", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing DTSTART"]) }

        let start = parseDateTime(dtStartRaw.0, tzid: dtStartRaw.1) ?? Date()
        let end: Date
        if let dtEndRaw = dtEnd, let d = parseDateTime(dtEndRaw.0, tzid: dtEndRaw.1) {
            end = d
        } else {
            end = Calendar.current.date(byAdding: .hour, value: 1, to: start)!
        }
        let fp = Fingerprint.eventHash(title: s, location: location, start: start, end: end)
        return Event(uid: uid, title: s, startDate: start, endDate: end, location: location, description: description, url: url, organizer: organizer, attendees: [], categories: [], status: status, created: created, lastModified: lastModified, sequence: sequence, fingerprint: fp)
    }

    func parseDateTime(_ value: String, tzid: String?) -> Date? {
        // Zulu form
        if value.hasSuffix("Z") {
            let fmt = DateFormatter()
            fmt.calendar = Calendar(identifier: .gregorian)
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.timeZone = TimeZone(secondsFromGMT: 0)
            fmt.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            return fmt.date(from: value)
        }
        // Date-time or date-only with optional TZID
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        if value.count == 8 { // YYYYMMDD (all-day)
            fmt.timeZone = tzid.flatMap { TimeZone(identifier: $0) } ?? TimeZone.current
            fmt.dateFormat = "yyyyMMdd"
            return fmt.date(from: value)
        }
        fmt.timeZone = tzid.flatMap { TimeZone(identifier: $0) } ?? TimeZone.current
        fmt.dateFormat = "yyyyMMdd'T'HHmmss"
        return fmt.date(from: value)
    }

    func unfoldLines(_ content: String) -> [String] {
        // Normalize line endings to \n and implement RFC5545 line unfolding
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var lines: [String] = []
        var current: String? = nil
        for raw in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(raw)
            if s.hasPrefix(" ") || s.hasPrefix("\t") {
                // Continuation line: append without leading whitespace
                let cont = s.trimmingCharacters(in: .whitespaces)
                if current != nil { current! += cont } else { current = cont }
            } else {
                if let cur = current { lines.append(cur) }
                current = s
            }
        }
        if let cur = current { lines.append(cur) }
        return lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func splitProperty(_ line: String) -> (String, [String: String], String) {
        // NAME;PARAM=VALUE;P2=V2:ACTUAL VALUE
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 else { return (line, [:], "") }
        let head = parts[0]
        let value = parts[1]
        var name = head
        var params: [String: String] = [:]
        if let semi = head.firstIndex(of: ";") {
            name = String(head[..<semi]).uppercased()
            let paramStr = head[semi...].dropFirst()
            for p in paramStr.split(separator: ";") {
                let kv = p.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 { params[kv[0].uppercased()] = kv[1] }
            }
        } else {
            name = head.uppercased()
        }
        return (name, params, value)
    }
}
