import ChickenKit
import SwiftData
import SwiftUI

struct ProfileView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(filter: #Predicate<Book> { $0.finishedAt != nil }, sort: \Book.finishedAt, order: .reverse)
    private var finished: [Book]
    @Query(sort: \Book.lastActivityAt, order: .reverse) private var allBooks: [Book]
    @Query(sort: \Highlight.createdAt, order: .reverse) private var highlights: [Highlight]
    var isPushed = false
    @State private var year = ReadingLog.Year()

    private var gutter: CGFloat { sizeClass == .compact ? 20 : 40 }
    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    private var finishedThisYear: [Book] {
        finished.filter { $0.finishedAt.map { Calendar.current.component(.year, from: $0) == currentYear } ?? false }
    }

    private var physicalCount: Int {
        allBooks.filter(\.isPhysical).count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                ChickenScreenHeader(
                    title: "Profile",
                    subtitle: physicalCount > 0
                        ? "\(allBooks.count) books · \(physicalCount) print · \(highlights.count) highlights"
                        : "\(allBooks.count) books · \(highlights.count) highlights"
                ) {
                    #if !os(macOS)
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            CircularGlassMenu(title: "Theme", systemImage: library.preferences.theme.systemImage) {
                                Picker("Theme", selection: Binding(
                                    get: { library.preferences.theme },
                                    set: { library.preferences.theme = $0 }
                                )) {
                                    ForEach(ReadingTheme.allCases) { theme in
                                        Label(theme.label, systemImage: theme.systemImage).tag(theme)
                                    }
                                }
                                .pickerStyle(.inline)
                            }
                            CircularGlassButton(
                                title: "Settings",
                                systemImage: "gearshape",
                                diameter: 38,
                                iconSize: 16
                            ) {
                                router.presentSheet(.settings)
                            }
                        }
                    }
                    #endif
                }
                .padding(.horizontal, gutter)

                timeRead
                    .padding(.horizontal, gutter)

                YearGoalCard(finished: finishedThisYear, goal: library.preferences.annualBookGoal)
                    .padding(.horizontal, gutter)

                notebookCard
                    .padding(.horizontal, gutter)

                if !finishedThisYear.isEmpty {
                    BookShelf(title: "Finished in \(String(currentYear))", books: finishedThisYear, gutter: gutter)
                }

                if hasTasteData {
                    ReadingTasteCard(books: allBooks)
                        .padding(.horizontal, gutter)
                }

                ReadingGoalsEditor()
                    .padding(.horizontal, gutter)
            }
            .padding(.top, sizeClass == .compact ? 6 : 20)
            .padding(.bottom, sizeClass == .compact ? 128 : 88)
            .frame(maxWidth: 1180, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .background(palette.background.ignoresSafeArea())
        .pageTitle("Profile")
        #if !os(macOS)
        .toolbar(!isPushed && sizeClass == .compact ? .hidden : .automatic, for: .navigationBar)
        #else
        .toolbar {
            ToolbarItemGroup(placement: LibraryToolbar.placement) {
                Menu {
                    Picker("Theme", selection: Binding(
                        get: { library.preferences.theme },
                        set: { library.preferences.theme = $0 }
                    )) {
                        ForEach(ReadingTheme.allCases) { theme in
                            Label(theme.label, systemImage: theme.systemImage).tag(theme)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Theme", systemImage: library.preferences.theme.systemImage)
                }

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        #endif
        .task(id: library.readingSecondsToday / 60) { year = library.readingYear() }
    }

    private var notebookCard: some View {
        NavigationLink {
            NotebookView()
        } label: {
            GoalCard {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notebook").chickenEyebrow(palette)
                        Text(highlights.isEmpty ? "No highlights yet" : "\(highlights.count) saved \(highlights.count == 1 ? "highlight" : "highlights")")
                            .font(.chickenUI(16, weight: .semibold))
                            .foregroundStyle(palette.text)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.muted)
                }
                if let highlight = highlights.first, let book = highlight.book {
                    HStack(alignment: .top, spacing: 12) {
                        Capsule()
                            .fill(highlight.color.bar)
                            .frame(width: 3)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(highlight.text)
                                .font(.chickenSerif(15.5))
                                .foregroundStyle(palette.text)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                            Text("\(book.displayTitle) · \(highlight.createdAt.formatted(.dateTime.month(.abbreviated).day()))")
                                .font(.chickenUI(12, weight: .medium))
                                .foregroundStyle(palette.muted)
                                .lineLimit(1)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(TactilePressStyle(scale: 0.99))
    }

    private var timeRead: some View {
        GoalCard {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 32) { figures }
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 18) {
                    GridRow {
                        figure("Today", library.readingSecondsToday)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        figure("This week", week)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GridRow {
                        figure(String(currentYear), year.totalSeconds)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        days
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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

    private var hasTasteData: Bool {
        allBooks.contains { !$0.genres.isEmpty || $0.releaseYear != nil }
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
        if hours < 10 {
            if minutes == 0 { return ("\(hours)", hours == 1 ? "hour" : "hours") }
            return ("\(hours)h \(minutes)m", "")
        }
        return ("\(hours)", "hours")
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
            if !unit.isEmpty {
                Text(unit)
                    .font(.chickenUI(13.5))
                    .foregroundStyle(palette.muted)
            }
        }
        .monospacedDigit()
    }
}

struct YearGoalCard: View {
    @Environment(\.palette) private var palette
    let finished: [Book]
    let goal: Int

    private var year: String { String(Calendar.current.component(.year, from: Date())) }

    private var pagesFinishedThisYear: Int {
        finished.compactMap(\.pageCount).filter { $0 > 0 }.reduce(0, +)
    }

    var body: some View {
        GoalCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(year) reading goal").chickenEyebrow(palette)
                GoalFigure(value: "\(finished.count)", unit: "of \(goal) books")
                if pagesFinishedThisYear > 0 {
                    Text("\(pagesFinishedThisYear.formatted()) pages read")
                        .font(.chickenMono(11.5))
                        .foregroundStyle(palette.muted)
                }
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

private struct ReadingTasteCard: View {
    @Environment(\.palette) private var palette
    let books: [Book]

    private var topGenres: [(name: String, count: Int)] {
        let active = books.filter { $0.isFinished || $0.progress > 0 }
        let pool = active.contains(where: { !$0.genres.isEmpty }) ? active : books
        var map: [String: (name: String, count: Int)] = [:]
        for book in pool {
            for genre in book.genres {
                let key = genre.lowercased()
                let prev = map[key]
                map[key] = (prev?.name ?? genre, (prev?.count ?? 0) + 1)
            }
        }
        return map.values
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.name < rhs.name
            }
            .prefix(5)
            .map { $0 }
    }

    private var eraAndLengthSummary: String? {
        let years = books.compactMap(\.releaseYear).sorted()
        let pages = books.compactMap(\.pageCount).filter { $0 > 0 }
        var parts: [String] = []
        if let minYear = years.first, let maxYear = years.last {
            let minDecade = (minYear / 10) * 10
            let maxDecade = (maxYear / 10) * 10
            parts.append(minDecade == maxDecade ? "\(minDecade)s" : "\(minDecade)s – \(maxDecade)s")
        }
        if !pages.isEmpty {
            let avg = pages.reduce(0, +) / pages.count
            parts.append("avg. \(avg) pages")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        let genres = topGenres
        if !genres.isEmpty || eraAndLengthSummary != nil {
            GoalCard {
                Text("What you read").chickenEyebrow(palette)
                if !genres.isEmpty {
                    let maxCount = max(1, genres.first?.count ?? 1)
                    VStack(spacing: 10) {
                        ForEach(genres, id: \.name) { item in
                            HStack(spacing: 12) {
                                Text(item.name)
                                    .font(.chickenUI(13.5, weight: .medium))
                                    .foregroundStyle(palette.text)
                                    .lineLimit(1)
                                    .frame(width: 120, alignment: .leading)
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(palette.surfaceAlt)
                                        Capsule()
                                            .fill(palette.ribbon)
                                            .frame(width: max(6, geo.size.width * CGFloat(item.count) / CGFloat(maxCount)))
                                    }
                                }
                                .frame(height: 6)
                                Text("\(item.count)")
                                    .font(.chickenMono(11.5, weight: .semibold))
                                    .foregroundStyle(palette.muted)
                                    .frame(width: 24, alignment: .trailing)
                            }
                        }
                    }
                }
                if let summary = eraAndLengthSummary {
                    Text(summary)
                        .font(.chickenMono(11.5))
                        .foregroundStyle(palette.faint)
                        .padding(.top, 2)
                }
            }
        }
    }
}

struct EggCarton: View {
    @Environment(\.palette) private var palette
    let laid: Int
    let total: Int

    var body: some View {
        let perRow = total <= 12 ? max(1, total) : min(12, (total + 1) / 2)
        let columns = Array(repeating: GridItem(.flexible(minimum: 12, maximum: 24), spacing: 6), count: perRow)
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
                .frame(maxWidth: 24)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(0..<12, id: \.self) { index in
                    let month = index + 1
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 3).fill(palette.surfaceAlt.opacity(0.65)).frame(width: 12, height: height)
                        if month <= currentMonth, seconds[index] > 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(month == currentMonth ? palette.ribbon : palette.muted.opacity(0.45))
                                .frame(width: 12, height: max(3, height * Double(seconds[index]) / Double(scale)))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Rectangle()
                .fill(palette.border)
                .frame(height: 0.5)
            HStack(spacing: 0) {
                ForEach(0..<12, id: \.self) { index in
                    let month = index + 1
                    Text(symbols[index])
                        .font(.chickenUI(9.5, weight: month == currentMonth ? .semibold : .medium))
                        .foregroundStyle(month == currentMonth ? palette.text : palette.faint)
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Calendar.current.monthSymbols[index])
                        .accessibilityValue("\(seconds[index] / 60) minutes")
                }
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
