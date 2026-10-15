import Foundation

public extension String {
    /// The title as Chicken shows it. Publishers often store titles in all
    /// caps ("HOW CHINA ESCAPED THE POVERTY TRAP"), which reads as shouting
    /// once it's set in a display face; those become title case. Titles with
    /// any lowercase letters are left exactly as the publisher wrote them.
    var readableTitle: String {
        guard contains(where: \.isUppercase), !contains(where: \.isLowercase) else { return self }
        let words = split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        // A single short word in caps is probably an acronym ("SPQR", "IT").
        if words.count == 1, count <= 4 { return self }

        var result: [String] = []
        var startsPhrase = true
        for (index, word) in words.enumerated() {
            let isLast = index == words.count - 1
            result.append(Self.titleCased(word, capitalizingMinor: startsPhrase || isLast))
            if !word.isEmpty { startsPhrase = word.last.map { ":—–?!.".contains($0) } ?? false }
        }
        return result.joined(separator: " ")
    }

    private static let minorWords: Set<String> = [
        "a", "an", "the", "and", "but", "or", "nor", "for", "so", "yet",
        "as", "at", "by", "in", "of", "off", "on", "per", "to", "up", "via", "vs", "vs.",
    ]

    private static func titleCased(_ word: String, capitalizingMinor: Bool) -> String {
        guard !word.isEmpty else { return word }
        // Roman numerals and words with digits ("II", "1984", "3D") stay as written.
        if word.allSatisfy({ "IVXLCDM".contains($0) }) || word.contains(where: \.isNumber) { return word }

        let lower = word.lowercased()
        let bare = lower.trimmingCharacters(in: .punctuationCharacters)
        if !capitalizingMinor, minorWords.contains(bare) { return lower }

        // Capitalize each hyphenated part: "SELF-HELP" → "Self-Help".
        return lower.split(separator: "-", omittingEmptySubsequences: false)
            .map { part in
                guard let first = part.firstIndex(where: \.isLetter) else { return String(part) }
                return part[..<first] + part[first].uppercased() + part[part.index(after: first)...]
            }
            .joined(separator: "-")
    }
}
