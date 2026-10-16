import ChickenKit
import SwiftData
import SwiftUI

/// Your reading: time read on every device, the year's clutch of finished
/// books, the latest line you marked, and the goals it's all measured by.
struct YourReadingView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.openBook) private var openBook
    @Query(filter: #Predicate<Book> { $0.finishedAt != nil }, sort: \Book.finishedAt, order: .reverse)
    private var finished: [Book]
    @Query(sort: \Highlight.createdAt, order: .reverse) private var highlights: [Highlight]
    @State private var year = ReadingLog.Year()

    private var gutter: CGFloat { sizeClass == .compact ? 20 : 40 }
    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    private var finishedThisYear: [Book] {
        finished.filter { $0.finishedAt.map { Calendar.current.component(.year, from: $0) == currentYear } ?? false }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                PageHeader(title: "Your Reading")
                    .padding(.horizontal, gutter)

                timeRead
                    .padding(.horizontal, gutter)

                YearGoalCard(finished: finishedThisYear, goal: library.preferences.annualBookGoal)
                    .padding(.horizontal, gutter)

                if !finishedThisYear.isEmpty {
                    BookShelf(title: "Finished in \(String(currentYear))", books: finishedThisYear, gutter: gutter)
                }

                if let highlight = highlights.first, let book = highlight.book {
                    latest(highlight, in: book)
                        .padding(.horizontal, gutter)
                }

                ReadingGoalsEditor()
                    .padding(.horizontal, gutter)
            }
            .padding(.top, sizeClass == .compact ? 4 : 20)
            .padding(.bottom, 80)
            .frame(maxWidth: 1180, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.hard, for: .top)
        .background(palette.background.ignoresSafeArea())
        .pageTitle("Your Reading")
        // Refreshes as today's minutes tick over while a reader is open.
        .task(id: library.readingSecondsToday / 60) { year = library.readingYear() }
    }

    // MARK: Time

    private var timeRead: some View {
        GoalCard {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 32) { figures }
                Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 18) {
                    GridRow { figure("Today", library.readingSecondsToday); figure("This week", week) }
                    GridRow { figure(String(currentYear), year.totalSeconds); days }
                }
            }
            MonthChart(seconds: year.monthSeconds, currentMonth: Calendar.current.component(.month, from: Date()))
                .padding(.top, 6)
        }
    }

    @ViewBuilder
    private var figures: some View {
        figure("Today", library.readingSecondsToday)
        figure("This week", week)
        figure(String(currentYear), year.totalSeconds)
        days
    }

    private var week: Int { library.lastSevenDays.reduce(0) { $0 + $1.seconds } }

    private func figure(_ label: String, _ seconds: Int) -> some View {
        let duration = Self.duration(seconds)
        return VStack(alignment: .leading, spacing: 10) {
            Text(label).chickenEyebrow(palette)
            GoalFigure(value: duration.value, unit: duration.unit)
        }
        .accessibilityElement(children: .combine)
    }

    private var days: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Days read").chickenEyebrow(palette)
            GoalFigure(value: "\(year.daysRead)", unit: year.daysRead == 1 ? "day" : "days")
        }
        .accessibilityElement(children: .combine)
    }

    /// Minutes under an hour, hours and minutes under ten, then hours.
    static func duration(_ seconds: Int) -> (value: String, unit: String) {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours == 0 { return (seconds > 0 && minutes == 0 ? "<1" : "\(minutes)", "min") }
        if hours < 10 { return ("\(hours)h \(minutes)", "min") }
        return ("\(hours)", "hours")
    }

    // MARK: Latest highlight

    private func latest(_ highlight: Highlight, in book: Book) -> some View {
        Button {
            if let location = highlight.location { book.lastLocation = location }
            library.save()
            openBook(book.id, from: nil)
        } label: {
            GoalCard {
                Text("Latest highlight").chickenEyebrow(palette)
                HStack(alignment: .top, spacing: 14) {
                    Capsule()
                        .fill(palette.ribbon)
                        .frame(width: 3)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(highlight.text)
                            .font(.chickenSerif(sizeClass == .compact ? 17 : 19))
                            .foregroundStyle(palette.text)
                            .lineLimit(6)
                            .multilineTextAlignment(.leading)
                        Text("\(book.displayTitle) · \(highlight.createdAt.formatted(.dateTime.month(.abbreviated).day()))")
                            .font(.chickenSerif(13, italic: true))
                            .foregroundStyle(palette.muted)
                            .lineLimit(1)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the book at this passage")
    }
}

/// A year in twelve columns; this month in ribbon, the months to come
/// as empty tracks.
private struct MonthChart: View {
    @Environment(\.palette) private var palette
    let seconds: [Int]
    let currentMonth: Int

    var body: some View {
        let height: CGFloat = 64
        let scale = max(seconds.max() ?? 0, 60)
        let symbols = Calendar.current.veryShortMonthSymbols
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(0..<12, id: \.self) { index in
                let month = index + 1
                VStack(spacing: 6) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 2).fill(palette.surfaceAlt).frame(width: 12, height: height)
                        if month <= currentMonth, seconds[index] > 0 {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(month == currentMonth ? palette.ribbon : palette.muted.opacity(0.55))
                                .frame(width: 12, height: max(3, height * Double(seconds[index]) / Double(scale)))
                        }
                    }
                    Text(symbols[index])
                        .font(.chickenUI(9.5, weight: month == currentMonth ? .bold : .medium))
                        .foregroundStyle(month == currentMonth ? palette.text : palette.faint)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Calendar.current.monthSymbols[index])
                .accessibilityValue("\(seconds[index] / 60) minutes")
            }
        }
    }
}

/// The daily minutes and books-per-year goals, with steppers.
struct ReadingGoalsEditor: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette

    var body: some View {
        let preferences = library.preferences
        ChickenSection("Goals", footer: "Reading time counts only while a book is open and in front of you.") {
            ChickenRow {
                row(
                    label: "Daily reading",
                    value: "\(preferences.dailyGoalMinutes)",
                    unit: "min",
                    canDecrease: preferences.dailyGoalMinutes > AppPreferences.dailyGoalRange.lowerBound,
                    canIncrease: preferences.dailyGoalMinutes < AppPreferences.dailyGoalRange.upperBound,
                    decrease: { preferences.dailyGoalMinutes -= 5 },
                    increase: { preferences.dailyGoalMinutes += 5 }
                )
            }
            ChickenRow(isLast: true) {
                row(
                    label: "Books this year",
                    value: "\(preferences.annualBookGoal)",
                    unit: preferences.annualBookGoal == 1 ? "book" : "books",
                    canDecrease: preferences.annualBookGoal > AppPreferences.annualGoalRange.lowerBound,
                    canIncrease: preferences.annualBookGoal < AppPreferences.annualGoalRange.upperBound,
                    decrease: { preferences.annualBookGoal -= 1 },
                    increase: { preferences.annualBookGoal += 1 }
                )
            }
        }
    }

    private func row(
        label: String, value: String, unit: String,
        canDecrease: Bool, canIncrease: Bool,
        decrease: @escaping () -> Void, increase: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.chickenUI(13))
                    .foregroundStyle(palette.muted)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.chickenDisplay(26))
                        .foregroundStyle(palette.text)
                        .contentTransition(.numericText())
                    Text(unit)
                        .font(.chickenSerif(14, italic: true))
                        .foregroundStyle(palette.muted)
                }
                .monospacedDigit()
            }
            Spacer()
            GlassStepper(label: label, canDecrease: canDecrease, canIncrease: canIncrease, decrease: {
                withAnimation(.snappy) { decrease() }
            }, increase: {
                withAnimation(.snappy) { increase() }
            })
        }
    }
}
