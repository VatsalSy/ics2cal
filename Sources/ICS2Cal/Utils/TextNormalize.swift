import Foundation

enum TextNormalize {
    static func norm(_ s: String) -> String {
        let lowered = s.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
        let folded = lowered.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        // Strip punctuation
        let stripped = folded.unicodeScalars.filter { !CharacterSet.punctuationCharacters.contains($0) }.map(String.init).joined()
        return dropCommonPrefixes(stripped)
    }

    private static func dropCommonPrefixes(_ s: String) -> String {
        let prefixes = ["seminar:", "talk:", "lecture:"]
        for p in prefixes {
            if s.hasPrefix(p) { return String(s.dropFirst(p.count)).trimmingCharacters(in: .whitespaces) }
        }
        return s
    }
}

