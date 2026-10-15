import ChickenKit
import SwiftUI

struct ContinueReadingCard: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette
    @Environment(\.openBook) private var openBook
    @Environment(\.horizontalSizeClass) private var sizeClass
    let book: Book

    var body: some View {
        Group {
            if sizeClass == .compact {
                compactLayout
            } else {
                regularLayout
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(palette.surface)
                .stroke(palette.border, lineWidth: 0.5)
                .shadow(color: palette.shadow, radius: 1, y: 1)
        )
    }

    private var regularLayout: some View {
        HStack(alignment: .top, spacing: 36) {
            BookCover(book: book, style: .hero)
                .frame(width: 190, height: 285)
                .onTapGesture { openBook(book.id) }

            details
                .frame(maxWidth: .infinity, alignment: .leading)

            DailyReadingPanel()
                .frame(width: 210)
        }
        .padding(32)
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 18) {
                BookCover(book: book, style: .tile)
                    .frame(width: 104, height: 156)
                    .onTapGesture { openBook(book.id) }
                details
            }
            DailyReadingPanel()
        }
        .padding(20)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Last opened · \(book.lastOpenedAt?.relativeDescription ?? "—")")
                .chickenEyebrow(palette)
                .lineLimit(1)
                .padding(.bottom, 10)

            Text(book.title)
                .font(.chickenSerif(sizeClass == .compact ? 22 : 34, weight: .medium))
                .tracking(-0.4)
                .foregroundStyle(palette.text)
                .lineLimit(3)
                .padding(.bottom, 6)

            Text(book.displayAuthor)
                .font(.chickenSerif(sizeClass == .compact ? 14 : 16, italic: true))
                .foregroundStyle(palette.muted)
                .lineLimit(1)
                .padding(.bottom, 22)

            VStack(alignment: .leading, spacing: 8) {
                ProgressLine(progress: book.progress, height: 3, fill: palette.text)
                HStack {
                    Text("\(Int((book.progress * 100).rounded()))% complete")
                    Spacer()
                    if let pages = book.pageCount, pages > 0 {
                        Text("page \(max(1, Int((Double(pages) * book.progress).rounded()))) of \(pages)")
                    }
                }
                .font(.chickenMono(11))
                .foregroundStyle(palette.faint)
            }
            .frame(maxWidth: 300)
            .padding(.bottom, 20)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { continueButton; meta }
                VStack(alignment: .leading, spacing: 12) { continueButton; meta }
            }
        }
    }

    private var continueButton: some View {
        PrimaryActionButton(title: "Continue reading", systemImage: "arrow.right") { openBook(book.id) }
    }

    @ViewBuilder
    private var meta: some View {
        HStack(spacing: 14) {
            if let pagesLeft = book.estimatedPagesLeft {
                Label(ReadingEstimate.duration(forPages: pagesLeft) + " left", systemImage: "clock")
            }
            if book.highlightCount > 0 {
                Label("\(book.highlightCount) highlights", systemImage: "highlighter")
            }
        }
        .font(.chickenUI(12))
        .foregroundStyle(palette.muted)
    }
}

// MARK: - Daily reading

struct DailyReadingPanel: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glint: CGFloat = -0.3
    @State private var hasShownGlint = false

    private var goalSeconds: Int { library.preferences.dailyGoalMinutes * 60 }
    private var seconds: Int { library.readingSecondsToday }
    private var fraction: Double { goalSeconds > 0 ? min(1, Double(seconds) / Double(goalSeconds)) : 0 }
    private var metGoal: Bool { goalSeconds > 0 && seconds >= goalSeconds }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reading today").chickenEyebrow(palette)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Self.durationLabel(seconds))
                    .font(.chickenSerif(22, weight: .medium))
                    .foregroundStyle(palette.text)
                    .contentTransition(.numericText())
                Text("/ \(library.preferences.dailyGoalMinutes) min")
                    .font(.chickenSerif(13, italic: true))
                    .foregroundStyle(palette.muted)
            }
            .monospacedDigit()

            ProgressLine(progress: fraction, height: 3, fill: palette.text)
                .overlay(alignment: .leading) {
                    // One sweep of light the moment the goal is reached.
                    GeometryReader { geometry in
                        LinearGradient(colors: [.clear, palette.background.opacity(0.6), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 60)
                            .offset(x: glint * geometry.size.width * fraction)
                            .mask(alignment: .leading) { Capsule().frame(width: geometry.size.width * fraction) }
                    }
                    .allowsHitTesting(false)
                    .opacity(reduceMotion ? 0 : 1)
                }
                .onChange(of: metGoal) { _, met in
                    guard met, !hasShownGlint, !reduceMotion else { return }
                    hasShownGlint = true
                    glint = -0.3
                    withAnimation(.easeOut(duration: 1.1)) { glint = 1.3 }
                }

            Text(caption)
                .font(.chickenSerif(12, italic: true))
                .foregroundStyle(palette.muted)

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(library.lastSevenDays) { day in
                    DaySparkBar(day: day, scale: weekScale, goalSeconds: goalSeconds)
                }
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.surfaceAlt.opacity(0.6))
                .stroke(palette.border, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }

    private var weekScale: Int {
        max(goalSeconds, library.lastSevenDays.map(\.seconds).max() ?? 0, 60)
    }

    private var caption: String {
        if goalSeconds <= 0 { return "Set a daily goal in Settings." }
        if metGoal { return "Goal met. Read on." }
        if seconds == 0 { return "Open a book to start." }
        let minutes = (goalSeconds - seconds + 59) / 60
        return minutes == 1 ? "One minute to go." : "\(minutes) minutes to go."
    }

    static func durationLabel(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) sec" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours) h \(minutes) min" : "\(minutes) min"
    }
}

private struct DaySparkBar: View {
    @Environment(\.palette) private var palette
    let day: DayReading
    let scale: Int
    let goalSeconds: Int

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 1.5).fill(palette.surfaceAlt).frame(width: 10, height: 26)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(day.isToday ? palette.text : (day.seconds == 0 ? palette.surfaceAlt : palette.muted))
                    .frame(width: 10, height: max(2, 26 * min(1, Double(day.seconds) / Double(max(scale, 1)))))
            }
            Circle()
                .fill(goalSeconds > 0 && day.seconds >= goalSeconds ? palette.text : palette.faint.opacity(0.35))
                .frame(width: 3, height: 3)
            Text(day.narrowWeekday)
                .font(.chickenMono(8, weight: day.isToday ? .semibold : .regular))
                .foregroundStyle(day.isToday ? palette.text : palette.faint)
        }
        .frame(width: 16)
        .accessibilityLabel("\(day.dayStart.formatted(.dateTime.weekday(.wide))): \(day.seconds / 60) minutes")
    }
}

// MARK: - Yearly goal

struct BooksThisYearStrip: View {
    @Environment(\.palette) private var palette
    @Environment(\.openBook) private var openBook
    let finished: [Book]
    let goal: Int

    private var fraction: Double { goal > 0 ? min(1, Double(finished.count) / Double(goal)) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("Books this year · \(String(Calendar.current.component(.year, from: Date())))")
                    .chickenEyebrow(palette)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(finished.count)")
                        .font(.chickenSerif(20, weight: .medium))
                        .foregroundStyle(palette.text)
                    Text("of \(goal)")
                        .font(.chickenSerif(13, italic: true))
                        .foregroundStyle(palette.muted)
                }
                .monospacedDigit()
            }

            ProgressLine(progress: fraction)

            Text(caption)
                .font(.chickenSerif(12, italic: true))
                .foregroundStyle(palette.muted)

            if !finished.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(finished) { book in
                            VStack(alignment: .leading, spacing: 6) {
                                BookCover(book: book, style: .mini)
                                    .frame(width: 60, height: 90)
                                Text(book.finishedAt?.formatted(.dateTime.month(.abbreviated)) ?? "")
                                    .font(.chickenMono(10))
                                    .foregroundStyle(palette.faint)
                            }
                            .onTapGesture { openBook(book.id) }
                            .accessibilityLabel("\(book.title), finished")
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    private var caption: String {
        guard goal > 0 else { return "Set a goal in Settings." }
        if finished.count >= goal { return "Goal met. Read on for the joy of it." }
        let remaining = goal - finished.count
        return remaining == 1 ? "1 book to go" : "\(remaining) books to go"
    }
}
