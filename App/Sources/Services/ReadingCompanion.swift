import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum ReadingCompanion {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        #endif
        return false
    }

    static func recap(
        title: String,
        author: String?,
        progress: Double,
        chapter: String?,
        highlights: [String]
    ) async throws -> String {
        #if canImport(FoundationModels)
        let session = LanguageModelSession(
            instructions: """
            You are a quiet, thoughtful reading companion inside an e-book reader.
            Write a concise 2 to 3 sentence spoiler-free recap to help the reader pick
            back up where they left off. Base it strictly on the provided title,
            reading position, and the reader's own saved highlights. Never spoil events
            beyond the reader's current progress. Plain prose only, no markdown or headings.
            """
        )

        var lines: [String] = ["Book: \(title)"]
        if let author, !author.isEmpty { lines.append("Author: \(author)") }
        lines.append("Progress: \(Int((progress * 100).rounded()))%")
        if let chapter, !chapter.isEmpty { lines.append("Current chapter: \(chapter)") }
        if !highlights.isEmpty {
            lines.append("Passages the reader highlighted:")
            for quote in highlights.prefix(6) {
                lines.append("- \"\(String(quote.prefix(220)))\"")
            }
        }

        let response = try await session.respond(to: lines.joined(separator: "\n"))
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        return ""
        #endif
    }

    static func briefOverview(title: String, author: String?) async throws -> String {
        #if canImport(FoundationModels)
        let session = LanguageModelSession(
            instructions: """
            Write a crisp, spoiler-free 2-sentence description of this book for a
            personal library card. If you are not sure about the book, say only what
            is clear from its title without inventing plot details. Plain prose only.
            """
        )
        let byline = author.flatMap { $0.isEmpty ? nil : " by \($0)" } ?? ""
        let response = try await session.respond(to: "Describe \"\(title)\"\(byline).")
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        return ""
        #endif
    }
}
