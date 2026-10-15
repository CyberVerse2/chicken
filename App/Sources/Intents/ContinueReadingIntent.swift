import AppIntents
import ChickenKit
import SwiftUI

struct ContinueReadingIntent: AppIntent {
    static let title: LocalizedStringResource = "Continue Reading"
    static let description = IntentDescription("Opens the book you were reading most recently, at your place.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.pendingDestination = .continueReading
        return .result()
    }
}

struct OpenBookIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Book"
    static let description = IntentDescription("Opens a book from your library at your place.")
    static let openAppWhenRun = true

    @Parameter(title: "Book")
    var book: BookEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$book)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.pendingDestination = .book(book.id)
        return .result()
    }
}

/// Opens the book you last highlighted, at that passage.
struct OpenLastHighlightIntent: AppIntent {
    static let title: LocalizedStringResource = "Open My Last Highlight"
    static let description = IntentDescription("Opens the book with your most recent highlight, at that passage.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let library = LibraryStore.shared
        let latest = library.allBooks()
            .flatMap { $0.highlights ?? [] }
            .max { $0.createdAt < $1.createdAt }
        guard let highlight = latest, let book = highlight.book else {
            return .result(dialog: "You haven't highlighted anything yet.")
        }
        if let location = highlight.location { book.lastLocation = location }
        library.save()
        AppRouter.shared.pendingDestination = .book(book.id)
        return .result(dialog: "Opening \(book.displayTitle).")
    }
}

/// "How much have I read today?" Answers without opening the app.
struct ReadingTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Reading Today"
    static let description = IntentDescription("Tells you how many minutes you've read today, against your daily goal.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog & ShowsSnippetView {
        let library = LibraryStore.shared
        library.recomputeReadingStats()
        let minutes = library.readingSecondsToday / 60
        let goal = library.preferences.dailyGoalMinutes
        let dialog: IntentDialog
        if goal > 0 && minutes >= goal {
            dialog = "You've read \(minutes) minutes today. Your \(goal)-minute goal is done."
        } else if minutes == 0 {
            dialog = "You haven't read yet today. Your goal is \(goal) minutes."
        } else {
            dialog = "You've read \(minutes) of \(goal) minutes today, \(goal - minutes) to go."
        }
        return .result(value: minutes, dialog: dialog) {
            ReadingTodaySnippet(minutes: minutes, goal: goal, days: library.lastSevenDays.map { $0.seconds / 60 })
        }
    }
}

struct MarkBookFinishedIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark Book as Finished"
    static let description = IntentDescription("Marks a book as finished, so it counts toward this year's goal.")

    @Parameter(title: "Book")
    var book: BookEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Mark \(\.$book) as finished")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let library = LibraryStore.shared
        guard let stored = library.book(id: book.id) else {
            return .result(dialog: "That book isn't in your library anymore.")
        }
        library.setFinished(true, for: stored)
        let finished = library.booksFinished().count
        let goal = library.preferences.annualBookGoal
        return .result(dialog: "Marked \(stored.displayTitle) as finished. That's \(finished) of \(goal) this year.")
    }
}

/// The answer card for "Reading Today": the goal ring and the week.
private struct ReadingTodaySnippet: View {
    let minutes: Int
    let goal: Int
    let days: [Int]

    private var fraction: Double { goal > 0 ? min(1, Double(minutes) / Double(goal)) : 0 }
    private let ribbon = Color(red: 0.8, green: 0.553, blue: 0.27)

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle().stroke(.secondary.opacity(0.25), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: max(0.02, fraction))
                    .stroke(ribbon, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(minutes)").font(.custom("Superclarendon-Regular", size: 22))
                    Text("of \(goal) min").font(.caption2).foregroundStyle(.secondary)
                }
                .monospacedDigit()
            }
            .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 6) {
                Text("This week").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                HStack(alignment: .bottom, spacing: 6) {
                    let scale = max(goal, days.max() ?? 0, 1)
                    ForEach(Array(days.enumerated()), id: \.offset) { index, value in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(index == days.count - 1 ? ribbon : .secondary.opacity(0.5))
                            .frame(width: 10, height: max(3, 44 * CGFloat(value) / CGFloat(scale)))
                    }
                }
                .frame(height: 44, alignment: .bottom)
            }
        }
        .padding()
    }
}

struct ChickenShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ContinueReadingIntent(),
            phrases: [
                "Continue reading in \(.applicationName)",
                "Open my book in \(.applicationName)",
            ],
            shortTitle: "Continue Reading",
            systemImageName: "book.pages"
        )
        AppShortcut(
            intent: OpenBookIntent(),
            phrases: [
                "Open \(\.$book) in \(.applicationName)",
                "Read \(\.$book) in \(.applicationName)",
            ],
            shortTitle: "Open Book",
            systemImageName: "book.closed"
        )
        AppShortcut(
            intent: ReadingTodayIntent(),
            phrases: [
                "How much have I read today in \(.applicationName)",
                "My reading today in \(.applicationName)",
            ],
            shortTitle: "Reading Today",
            systemImageName: "chart.bar"
        )
        AppShortcut(
            intent: OpenLastHighlightIntent(),
            phrases: [
                "Open my last highlight in \(.applicationName)",
            ],
            shortTitle: "Last Highlight",
            systemImageName: "highlighter"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .orange
}
