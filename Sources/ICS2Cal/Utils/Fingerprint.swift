import Foundation

enum Fingerprint {
    static func fnv1a64(_ s: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3
        for b in s.utf8 { hash ^= UInt64(b); hash &*= prime }
        let hex = String(hash, radix: 16, uppercase: false)
        let pad = String(repeating: "0", count: max(0, 16 - hex.count))
        return pad + hex
    }

    static func eventHash(title: String, location: String?, start: Date, end: Date, isAllDay: Bool) -> String {
        let base = hashComponents(title: title, location: location, start: start, end: end)
        let flag = isAllDay ? "A" : "T"
        return fnv1a64("\(flag)|\(base)")
    }

    static func legacyEventHash(title: String, location: String?, start: Date, end: Date) -> String {
        fnv1a64(hashComponents(title: title, location: location, start: start, end: end))
    }

    private static func hashComponents(title: String, location: String?, start: Date, end: Date) -> String {
        let durMin = max(0, Int(end.timeIntervalSince(start) / 60))
        let startMinUTC = Int(start.timeIntervalSince1970 / 60)
        let t = TextNormalize.norm(title)
        let l = TextNormalize.norm(location ?? "")
        return "\(startMinUTC)|\(durMin)|\(t)|\(l)"
    }
}
