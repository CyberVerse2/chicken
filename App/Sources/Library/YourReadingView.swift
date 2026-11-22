import ChickenKit
import SwiftData
import SwiftUI

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
            VStack(alignment: .leading, spacing: 26) {
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
            .padding(.top, sizeClass == .compact ? 6 : 20)
            .padding(.bottom, 92)
            .frame(maxWidth: 1180, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.hard, for: .top)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .background(palette.background.ignoresSafeArea())
        .pageTitle("Your Reading")
        .task(id: library.readingSecondsToday / 60) { year = library.readingYear() }
    }

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
            if library.preferences.hasCalibratedPace {
                let pagesPerHour = Int((60.0 / library.preferences.minutesPerPage).rounded())
                Text("Calibrated pace · ~\(pagesPerHour) pages/hr")
                    .font(.chickenMono(11))
                    .foregroundStyle(palette.faint)
            }
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
        return VStack(alignment: .leading, spacing: 8) {
            Text(label).chickenEyebrow(palette)
            GoalFigure(value: duration.value, unit: duration.unit)
        }
        .accessibilityElement(children: .combine)
    }

    private var days: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Days read").chickenEyebrow(palette)
            GoalFigure(value: "\(year.daysRead)", unit: year.daysRead == 1 ? "day" : "days")
        }
        .accessibilityElement(children: .combine)
    }

    static func duration(_ seconds: Int) -> (value: String, unit: String) {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours == 0 { return (seconds > 0 && minutes == 0 ? "<1" : "\(minutes)", "min") }
        if hours < 10 { return ("\(hours)h \(minutes)", "min") }
        return ("\(hours)", "hours")
    }

    private func latest(_ highlight: Highlight, in book: Book) -> some View {
        Button {
            openBook(book.id, jumpTo: JumpTarget(location: highlight.location, chapterIndex: highlight.chapterIndex))
        } label: {
            GoalCard {
                Text("Latest highlight").chickenEyebrow(palette)
                HStack(alignment: .top, spacing: 14) {
                    Capsule()
                        .fill(palette.ribbon)
                        .frame(width: 3)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(highlight.text)
                            .font(.chickenSerif(sizeClass == .compact ? 17 : 18.5))
                            .foregroundStyle(palette.text)
                            .lineLimit(6)
                            .multilineTextAlignment(.leading)
                        Text("\(book.displayTitle) · \(highlight.createdAt.formatted(.dateTime.month(.abbreviated).day()))")
                            .font(.chickenUI(12.5, weight: .medium))
                            .foregroundStyle(palette.muted)
                            .lineLimit(1)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(TactilePressStyle(scale: 0.99))
        .accessibilityHint("Opens the book at this passage")
    }
}

struct GoalCard<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(palette.surface)
                    .stroke(palette.border, lineWidth: 0.5)
            )
    }
}

struct GoalFigure: View {
    @Environment(\.palette) private var palette
    let value: String
    let unit: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value)
                .font(.chickenDisplay(30))
                .tracking(-0.6)
                .foregroundStyle(palette.text)
                .contentTransition(.numericText())
            Text(unit)
                .font(.chickenUI(13.5))
                .foregroundStyle(palette.muted)
        }
        .monospacedDigit()
    }
}

struct YearGoalCard: View {
    @Environment(\.palette) private var palette
    let finished: [Book]
    let goal: Int

    private var year: String { String(Calendar.current.component(.year, from: Date())) }

    var body: some View {
        GoalCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(year) reading goal").chickenEyebrow(palette)
                GoalFigure(value: "\(finished.count)", unit: "of \(goal) books")
            }

            if goal <= 24 {
                EggCarton(laid: finished.count, total: goal)
            } else {
                ProgressLine(progress: goal > 0 ? min(1, Double(finished.count) / Double(goal)) : 0, height: 3)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct EggCarton: View {
    @Environment(\.palette) private var palette
    let laid: Int
    let total: Int

    var body: some View {
        let perRow = total <= 12 ? max(1, total) : min(12, (total + 1) / 2)
        let columns = Array(repeating: GridItem(.flexible(minimum: 12, maximum: 20), spacing: 6), count: perRow)
        LazyVGrid(columns: columns, alignment: .leading, spacing: 7) {
            ForEach(0..<total, id: \.self) { index in
                let filled = index < laid
                ZStack {
                    EggShape()
                        .fill(filled ? palette.ribbon : palette.surfaceAlt)
                    if !filled {
                        EggShape().stroke(palette.border, lineWidth: 0.5)
                    }
                }
                .aspectRatio(0.78, contentMode: .fit)
                .frame(maxWidth: 20)
            }
        }
        .frame(maxWidth: CGFloat(perRow) * 26, alignment: .leading)
        .accessibilityHidden(true)
    }
}

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
                        RoundedRectangle(cornerRadius: 3).fill(palette.surfaceAlt).frame(width: 12, height: height)
                        if month <= currentMonth, seconds[index] > 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(month == currentMonth ? palette.ribbon : palette.muted.opacity(0.45))
                                .frame(width: 12, height: max(3, height * Double(seconds[index]) / Double(scale)))
                        }
                    }
                    Text(symbols[index])
                        .font(.chickenUI(9.5, weight: month == currentMonth ? .semibold : .medium))
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

struct ReadingGoalsEditor: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(value)
                        .font(.chickenDisplay(26))
                        .foregroundStyle(palette.text)
                        .contentTransition(.numericText())
                    Text(unit)
                        .font(.chickenUI(13.5))
                        .foregroundStyle(palette.muted)
                }
                .monospacedDigit()
            }
            Spacer()
            GlassStepper(label: label, canDecrease: canDecrease, canIncrease: canIncrease, decrease: {
                withAnimation(reduceMotion ? nil : ChickenMotion.snappy) { decrease() }
            }, increase: {
                withAnimation(reduceMotion ? nil : ChickenMotion.snappy) { increase() }
            })
        }
    }
}
