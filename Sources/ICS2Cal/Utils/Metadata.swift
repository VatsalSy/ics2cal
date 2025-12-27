import Foundation

struct Meta: Codable {
    var v: Int = 1
    var hash: String
    var sources: [String]
    var uids: [String]
    var seen: [String: String] // source -> ISO timestamp
}

enum MetadataNotes {
    static let startMarker = "--- ics2cal ---"
    static let endMarker = "--- /ics2cal ---"

    static func encode(meta: Meta, into existingNotes: String?) -> String {
        let base = strip(existingNotes ?? "")
        guard let data = try? JSONEncoder().encode(meta),
              let json = String(data: data, encoding: .utf8) else {
            return base  // Encoding failed, return base without markers
        }
        if base.isEmpty {
            return [startMarker, json, endMarker].joined(separator: "\n")
        }
        return [base, startMarker, json, endMarker].joined(separator: "\n")
    }

    static func decode(from notes: String?) -> Meta? {
        guard let notes = notes else { return nil }
        guard let rangeStart = notes.range(of: startMarker) else { return nil }
        // Search for endMarker only AFTER startMarker
        let searchRange = rangeStart.upperBound..<notes.endIndex
        guard let rangeEnd = notes.range(of: endMarker, range: searchRange) else { return nil }
        let json = String(notes[rangeStart.upperBound..<rangeEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return try? JSONDecoder().decode(Meta.self, from: Data(json.utf8))
    }

    static func strip(_ notes: String) -> String {
        guard let rangeStart = notes.range(of: startMarker) else { return notes }
        // Search for endMarker only AFTER startMarker
        let searchRange = rangeStart.upperBound..<notes.endIndex
        guard let rangeEnd = notes.range(of: endMarker, range: searchRange) else { return notes }
        var n = notes
        n.removeSubrange(rangeStart.lowerBound..<rangeEnd.upperBound)
        return n.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

