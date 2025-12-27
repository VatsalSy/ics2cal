import Foundation

enum TextNormalize {
    static func norm(_ s: String) -> String {
        // 1. Case/diacritic folding with deterministic locale
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        // 2. Drop prefixes (before punctuation removal so colons are visible)
        let prefixDropped = dropCommonPrefixes(folded)
        // 3. Strip punctuation
        let stripped = prefixDropped.unicodeScalars.filter { !CharacterSet.punctuationCharacters.contains($0) }.map(String.init).joined()
        // 4. Trim ends and collapse whitespace
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private static func dropCommonPrefixes(_ s: String) -> String {
        let prefixes = ["seminar:", "talk:", "lecture:"]
        for p in prefixes {
            if s.hasPrefix(p) { return String(s.dropFirst(p.count)).trimmingCharacters(in: .whitespaces) }
        }
        return s
    }
}

