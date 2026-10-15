import ChickenKit
import SwiftUI

/// The book you're in the middle of (or the one to begin), set out on the
/// table rather than boxed in a card: a large cover with its ribbon, the
/// title in the display face, and one clear way back in.
struct ContinueReadingCard: View {
    enum Mode { case continuing, starting }

    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette
    @Environment(\.openBook) private var openBook
    @Environment(\.horizontalSizeClass) private var sizeClass
    let book: Book
    var mode: Mode = .continuing
    @State private var hovering = false

    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        Group {
            if isCompact { compactLayout } else { regularLayout }
        }
        .bookContextMenu(book)
    }

    // MARK: Layouts

    private var regularLayout: some View {
        HStack(alignment: .center, spacing: 52) {
            cover(width: 210)
            VStack(alignment: .leading, spacing: 0) {
                eyebrow.padding(.bottom, 14)
                Text(book.title)
                    .font(.chickenDisplay(40))
                    .tracking(-0.8)
                    .foregroundStyle(palette.text)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)
                Text(book.displayAuthor)
                    .font(.chickenSerif(20, italic: true))
                    .foregroundStyle(palette.muted)
                    .padding(.bottom, book.summary == nil ? 30 : 18)
                if let summary = book.summary, !summary.isEmpty {
                    Text(summary.replacingOccurrences(of: "\n", with: " "))
                        .font(.chickenSerif(15.5))
                        .foregroundStyle(palette.muted)
                        .lineSpacing(5)
                        .lineLimit(3)
                        .frame(maxWidth: 540, alignment: .leading)
                        .padding(.bottom, 28)
                }
                if mode == .continuing {
                    progress.frame(maxWidth: 420).padding(.bottom, 28)
                }
                HStack(spacing: 12) {
                    PrimaryActionButton(title: actionTitle, systemImage: "arrow.right") { openBook(book.id) }
                    detailsButton
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    private var compactLayout: some View {
        VStack(spacing: 0) {
            cover(width: 148)
                .padding(.bottom, 34)
            eyebrow.padding(.bottom, 10)
            Text(book.title)
                .font(.chickenDisplay(28))
                .tracking(-0.5)
                .foregroundStyle(palette.text)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.75)
                .padding(.bottom, 6)
            Text(book.displayAuthor)
                .font(.chickenSerif(17, italic: true))
                .foregroundStyle(palette.muted)
                .lineLimit(1)
                .padding(.bottom, 22)
            if mode == .continuing {
                progress.padding(.bottom, 22)
            }
            HStack(spacing: 10) {
                Button { openBook(book.id) } label: {
                    HStack(spacing: 8) {
                        Text(actionTitle)
                        Image(systemName: "arrow.right").font(.system(size: 13, weight: .semibold))
                    }
                    .font(.chickenUI(16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(palette.text)
                .foregroundStyle(palette.background)
                detailsButton
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Parts

    private func cover(width: CGFloat) -> some View {
        Button { openBook(book.id) } label: {
            BookCover(book: book, style: .hero)
                .frame(width: width, height: width * 1.5)
                .shadow(color: palette.shadow.opacity(0.9), radius: 2, x: 1, y: 1)
                .shadow(color: palette.shadow, radius: hovering ? 30 : 22, x: 4, y: hovering ? 22 : 16)
                .coverRibbon(mode == .continuing, length: width * 0.16, width: width * 0.075)
                .rotation3DEffect(.degrees(hovering ? -6 : 0), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.6)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.35), value: hovering)
        .accessibilityLabel("Open \(book.title)")
    }

    private var actionTitle: String {
        mode == .continuing ? "Continue reading" : "Begin reading"
    }

    private var eyebrow: some View {
        Group {
            switch mode {
            case .starting:
                Text("Something new")
            case .continuing:
                Text(book.lastOpenedAt.map { "Where you left off · \(Self.shortAgo($0))" } ?? "Where you left off")
            }
        }
        .chickenEyebrow(palette, color: palette.ribbon)
        .lineLimit(1)
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 9) {
            ProgressLine(progress: book.progress, height: 3)
            HStack(spacing: 6) {
                Text("\(Int((book.progress * 100).rounded()))%")
                    .foregroundStyle(palette.text)
                    .fontWeight(.semibold)
                if let pages = book.pageCount, pages > 0 {
                    Text("· p. \(max(1, Int((Double(pages) * book.progress).rounded()))) of \(pages)")
                }
                Spacer(minLength: 8)
                if let left = book.estimatedPagesLeft {
                    Text(ReadingEstimate.duration(forPages: left) + " left")
                }
            }
            .font(.chickenMono(12))
            .foregroundStyle(palette.muted)
        }
    }

    private var detailsButton: some View {
        Button("Details", systemImage: "info") { router.detailBookID = book.id }
            .labelStyle(.iconOnly)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(palette.text)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            #if os(macOS)
            .controlSize(.large)
            #endif
    }

    static func shortAgo(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 90 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Goals

/// Today's reading time beside the year's clutch of finished books.
struct GoalsRow: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let finishedThisYear: [Book]
    let annualGoal: Int

    var body: some View {
        if sizeClass == .compact {
            VStack(spacing: 14) {
                DailyReadingCard()
                YearGoalCard(finished: finishedThisYear, goal: annualGoal)
            }
        } else {
            HStack(alignment: .top, spacing: 20) {
                DailyReadingCard()
                YearGoalCard(finished: finishedThisYear, goal: annualGoal)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct GoalCard<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(palette.surface)
                    .stroke(palette.border, lineWidth: 0.5)
            )
    }
}

/// A large figure in the display face over an italic unit.
private struct GoalFigure: View {
    @Environment(\.palette) private var palette
    let value: String
    let unit: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value)
                .font(.chickenDisplay(34))
                .foregroundStyle(palette.text)
                .contentTransition(.numericText())
            Text(unit)
                .font(.chickenSerif(14.5, italic: true))
                .foregroundStyle(palette.muted)
        }
        .monospacedDigit()
    }
}

struct DailyReadingCard: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette

    private var goalSeconds: Int { library.preferences.dailyGoalMinutes * 60 }
    private var seconds: Int { library.readingSecondsToday }
    private var metGoal: Bool { goalSeconds > 0 && seconds >= goalSeconds }

    var body: some View {
        GoalCard {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Reading today").chickenEyebrow(palette)
                    GoalFigure(value: Self.durationLabel(seconds), unit: "of \(library.preferences.dailyGoalMinutes) min")
                }
                Spacer(minLength: 12)
                week
            }

            Text(caption)
                .font(.chickenSerif(13.5, italic: true))
                .foregroundStyle(palette.muted)
        }
        .accessibilityElement(children: .combine)
    }

    /// Seven days as columns against a dotted goal line; today in ribbon.
    private var week: some View {
        let days = library.lastSevenDays
        let height: CGFloat = 46
        let scale = max(goalSeconds, days.map(\.seconds).max() ?? 0, 60)
        let goalY = height * (1 - min(1, Double(goalSeconds) / Double(scale)))
        return HStack(alignment: .bottom, spacing: 7) {
            ForEach(days) { day in
                VStack(spacing: 5) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 2).fill(palette.surfaceAlt).frame(width: 9, height: height)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(day.isToday ? palette.ribbon : palette.muted.opacity(0.55))
                            .frame(width: 9, height: day.seconds == 0 ? 0 : max(3, height * min(1, Double(day.seconds) / Double(scale))))
                    }
                    Text(day.narrowWeekday)
                        .font(.chickenUI(9, weight: day.isToday ? .bold : .medium))
                        .foregroundStyle(day.isToday ? palette.text : palette.faint)
                }
                .accessibilityLabel("\(day.dayStart.formatted(.dateTime.weekday(.wide))): \(day.seconds / 60) minutes")
            }
        }
        .overlay(alignment: .top) {
            if goalSeconds > 0 {
                Line()
                    .stroke(palette.faint, style: StrokeStyle(lineWidth: 0.75, dash: [2, 2.5]))
                    .frame(height: 1)
                    .offset(y: goalY)
                    .accessibilityHidden(true)
            }
        }
    }

    private var caption: String {
        if goalSeconds <= 0 { return "Set a daily goal in Settings." }
        if metGoal { return "Done for today. Read on for the joy of it." }
        if seconds == 0 { return "Open a book to begin today's reading." }
        let minutes = (goalSeconds - seconds + 59) / 60
        return minutes == 1 ? "One minute to go." : "\(minutes) minutes to go."
    }

    static func durationLabel(_ seconds: Int) -> String {
        if seconds < 60 { return seconds == 0 ? "0" : "<1" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)" : "\(minutes)"
    }
}

nonisolated private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

/// The year's goal as a clutch of eggs in a carton: one egg laid for every
/// book finished. Goals too large for a carton fall back to a meter.
struct YearGoalCard: View {
    @Environment(\.palette) private var palette
    let finished: [Book]
    let goal: Int

    private var year: String { String(Calendar.current.component(.year, from: Date())) }

    var body: some View {
        GoalCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("The \(year) clutch").chickenEyebrow(palette)
                GoalFigure(value: "\(finished.count)", unit: "of \(goal) \(goal == 1 ? "book" : "books") finished")
            }

            if goal <= 24 {
                EggCarton(laid: finished.count, total: goal)
            } else {
                ProgressLine(progress: goal > 0 ? min(1, Double(finished.count) / Double(goal)) : 0, height: 3)
            }

            Text(caption)
                .font(.chickenSerif(13.5, italic: true))
                .foregroundStyle(palette.muted)
        }
        .accessibilityElement(children: .combine)
    }

    private var caption: String {
        guard goal > 0 else { return "Set a goal in Settings." }
        if finished.count >= goal { return "The carton's full. Every book from here is a bonus." }
        let remaining = goal - finished.count
        let monthsLeft = 12 - Calendar.current.component(.month, from: Date()) + 1
        let pace = Double(remaining) / Double(max(monthsLeft, 1))
        let paceText = pace <= 1 ? "about one a month" : "about \(Int(pace.rounded(.up))) a month"
        return "\(remaining) to go, \(paceText)."
    }
}

/// Rows of six egg cups, filled left to right.
struct EggCarton: View {
    @Environment(\.palette) private var palette
    let laid: Int
    let total: Int

    var body: some View {
        let perRow = total <= 6 ? total : (total <= 12 ? (total + 1) / 2 : 6 * ((total + 11) / 12))
        let columns = Array(repeating: GridItem(.flexible(minimum: 10, maximum: 22), spacing: 6), count: max(1, min(perRow, 12)))
        LazyVGrid(columns: columns, alignment: .leading, spacing: 7) {
            ForEach(0..<total, id: \.self) { index in
                let filled = index < laid
                ZStack {
                    EggShape()
                        .fill(filled ? palette.text : palette.surfaceAlt)
                    if !filled {
                        EggShape().stroke(palette.border, lineWidth: 0.5)
                    }
                }
                .aspectRatio(0.78, contentMode: .fit)
                .frame(maxWidth: 22)
            }
        }
        .frame(maxWidth: CGFloat(min(perRow, 12)) * 28, alignment: .leading)
        .accessibilityHidden(true)
    }
}
