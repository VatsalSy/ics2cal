import Foundation

enum Fingerprint {
    static func fnv1a64(_ s: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3
        for b in s.utf8 { hash ^= UInt64(b); hash &*= prime }
        return String(format: "%016llx", hash)
    }

    static func eventHash(title: String, location: String?, start: Date, end: Date) -> String {
        let durMin = max(0, Int(end.timeIntervalSince(start) / 60))
        let startMinUTC = Int(start.timeIntervalSince1970 / 60)
        let t = TextNormalize.norm(title)
        let l = TextNormalize.norm(location ?? "")
        return fnv1a64("\(startMinUTC)|\(durMin)|\(t)|\(l)")
    }
}

