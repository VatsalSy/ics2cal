import Foundation

struct ICSParseOptions {
    var maxEvents: Int = 10_000
    var maxLineLength: Int = 1_000_000  // 1MB safety limit
}

final class ICSParser {
    private static let utcFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return fmt
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone.current
        fmt.dateFormat = "yyyyMMdd'T'HHmmss"
        return fmt
    }()

    private static let dateOnlyFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone.current
        fmt.dateFormat = "yyyyMMdd"
        return fmt
    }()

    func parse(fileURL: URL, options: ICSParseOptions = ICSParseOptions()) throws -> [Event] {
        let data = try Data(contentsOf: fileURL)
        let encodingsTried = ["utf8", "isoLatin1"]
        let content: String
        if let utf8 = String(data: data, encoding: .utf8) {
            content = utf8
        } else if let latin = String(data: data, encoding: .isoLatin1) {
            content = latin
        } else {
            var info: [String: Any] = [NSLocalizedDescriptionKey: "Unable to decode file contents"]
            info["attemptedEncodings"] = encodingsTried
            info["fileURL"] = fileURL.path
            throw NSError(domain: "ICS", code: 1, userInfo: info)
        }
        let lines = try unfoldLines(content, maxLineLength: options.maxLineLength)
        var events: [Event] = []
        var buf: [String] = []
        var inEvent = false
        for line in lines {
            if line == "BEGIN:VEVENT" { inEvent = true; buf = []; continue }
            if line == "END:VEVENT" {
                inEvent = false
                let e = try parseVEvent(buf)
                events.append(e)
                if events.count >= options.maxEvents {
                    throw NSError(domain: "ICS", code: 10, userInfo: [NSLocalizedDescriptionKey: "Exceeded maximum event limit (\(options.maxEvents))"])
                }
                buf = []
                continue
            }
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
        var dtStart: (value: String, tzid: String?, isDateOnly: Bool)?
        var dtEnd: (value: String, tzid: String?, isDateOnly: Bool)?

        for raw in lines {
            let (name, params, value) = splitProperty(raw)
            switch name {
            case "UID": uid = value
            case "SUMMARY": summary = value
            case "DESCRIPTION": description = unescapeICSText(value)
            case "LOCATION": location = unescapeICSText(value)
            case "URL": url = URL(string: value)
            case "ORGANIZER": organizer = unescapeICSText(value)
            case "STATUS": status = EventStatus(rawValue: value.uppercased()) ?? status
            case "CREATED": created = parseDateTime(value, tzid: params["TZID"])
            case "LAST-MODIFIED": lastModified = parseDateTime(value, tzid: params["TZID"])
            case "SEQUENCE": sequence = Int(value) ?? sequence
            case "DTSTART": dtStart = (value, params["TZID"], isDateOnly(value: value, params: params))
            case "DTEND": dtEnd = (value, params["TZID"], isDateOnly(value: value, params: params))
            default: continue
            }
        }

        guard let s = summary else { throw NSError(domain: "ICS", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing SUMMARY"]) }
        guard let dtStartRaw = dtStart else { throw NSError(domain: "ICS", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing DTSTART"]) }

        guard let start = parseDateTime(dtStartRaw.value, tzid: dtStartRaw.tzid) else {
            throw NSError(domain: "ICS", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid DTSTART: \(dtStartRaw.value)"])
        }
        var isAllDay = dtStartRaw.isDateOnly
        let end: Date
        if let dtEndRaw = dtEnd {
            guard let parsedEnd = parseDateTime(dtEndRaw.value, tzid: dtEndRaw.tzid) else {
                throw NSError(domain: "ICS", code: 5, userInfo: [NSLocalizedDescriptionKey: "Invalid DTEND: \(dtEndRaw.value)"])
            }
            isAllDay = isAllDay || dtEndRaw.isDateOnly
            end = parsedEnd
        } else {
            let delta: TimeInterval = isAllDay ? 24 * 60 * 60 : 60 * 60
            end = start.addingTimeInterval(delta)
        }
        let fp = Fingerprint.eventHash(title: s, location: location, start: start, end: end, isAllDay: isAllDay)
        return Event(uid: uid, title: s, startDate: start, endDate: end, isAllDay: isAllDay, location: location, description: description, url: url, organizer: organizer, attendees: [], categories: [], status: status, created: created, lastModified: lastModified, sequence: sequence, fingerprint: fp)
    }

    func parseDateTime(_ value: String, tzid: String?) -> Date? {
        // Zulu form
        if value.hasSuffix("Z") {
            return ICSParser.utcFormatter.date(from: value)
        }
        // Date-time or date-only with optional TZID
        let tz = tzid.flatMap { TimeZone(identifier: $0) } ?? TimeZone.current
        if value.count == 8 && value.allSatisfy({ $0.isNumber }) {
            let fmt = ICSParser.dateOnlyFormatter.copy() as! DateFormatter
            fmt.timeZone = tz
            return fmt.date(from: value)
        }
        let fmt = ICSParser.dateTimeFormatter.copy() as! DateFormatter
        fmt.timeZone = tz
        return fmt.date(from: value)
    }

    func unfoldLines(_ content: String, maxLineLength: Int = 1_000_000) throws -> [String] {
        // Normalize line endings to \n and implement RFC5545 line unfolding
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var lines: [String] = []
        var current: String?
        for raw in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            var s = String(raw)
            if let first = s.first, first == " " || first == "\t" {
                s.removeFirst()
                if let cur = current {
                    current = cur + s
                } else {
                    current = s
                }
            } else {
                if let cur = current {
                    if cur.count > maxLineLength {
                        throw NSError(domain: "ICS", code: 11, userInfo: [NSLocalizedDescriptionKey: "Line exceeds maximum length (\(maxLineLength))"])
                    }
                    lines.append(cur)
                }
                current = s
            }
        }
        if let cur = current {
            if cur.count > maxLineLength {
                throw NSError(domain: "ICS", code: 11, userInfo: [NSLocalizedDescriptionKey: "Line exceeds maximum length (\(maxLineLength))"])
            }
            lines.append(cur)
        }
        return lines
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

    private func unescapeICSText(_ value: String) -> String {
        var result = String()
        result.reserveCapacity(value.count)

        var index = value.startIndex
        while index < value.endIndex {
            let ch = value[index]

            if ch == "\\" {
                let nextIndex = value.index(after: index)
                if nextIndex < value.endIndex {
                    let next = value[nextIndex]
                    switch next {
                    case "n", "N":
                        result.append("\n")
                    case ";":
                        result.append(";")
                    case ",":
                        result.append(",")
                    case "\\":
                        result.append("\\")
                    default:
                        // Unknown escape: keep backslash and following char
                        result.append(ch)
                        result.append(next)
                    }
                    index = value.index(after: nextIndex)
                    continue
                } else {
                    // Trailing backslash: keep as-is
                    result.append(ch)
                    index = nextIndex
                    continue
                }
            } else {
                result.append(ch)
                index = value.index(after: index)
            }
        }

        return result
    }

    private func isDateOnly(value: String, params: [String: String]) -> Bool {
        if let val = params["VALUE"], val.uppercased() == "DATE" { return true }
        return value.count == 8 && value.allSatisfy({ $0.isNumber })
    }
}
