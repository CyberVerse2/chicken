import ChickenKit
import SwiftUI

struct PhysicalBookLogSheet: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let book: Book
    var onFinished: ((Book) -> Void)? = nil

    @State private var totalPagesText: String
    @State private var currentPageText: String
    @State private var percentValue: Double

    @State private var addedMinutes: Int = 0
    @State private var timerRunning = false
    @State private var timerStartedAt: Date?
    @State private var accumulatedTimerSeconds: TimeInterval = 0

    @State private var quoteText = ""
    @State private var quoteNote = ""
    @State private var quoteColor: HighlightColor = .amber

    init(book: Book, onFinished: ((Book) -> Void)? = nil) {
        self.book = book
        self.onFinished = onFinished
        let total = book.pageCount
        _totalPagesText = State(initialValue: total.map(String.init) ?? "")
        let initialPercent = min(max(book.progress, 0), 1)
        _percentValue = State(initialValue: initialPercent)
        if let total, total > 0 {
            let page = book.isFinished ? total : Int((Double(total) * initialPercent).rounded())
            _currentPageText = State(initialValue: String(page))
        } else {
            _currentPageText = State(initialValue: "")
        }
    }

    private var effectiveTotalPages: Int? {
        guard let value = Int(totalPagesText.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else {
            return nil
        }
        return value
    }

    private var parsedCurrentPage: Int? {
        guard let value = Int(currentPageText.trimmingCharacters(in: .whitespacesAndNewlines)), value >= 0 else {
            return nil
        }
        return value
    }

    private func totalSessionSeconds(at date: Date) -> Int {
        let live = timerStartedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0
        return (addedMinutes * 60) + Int((accumulatedTimerSeconds + live).rounded())
    }

    var body: some View {
        NavigationStack {
            ChickenPage(
                title: "Log Reading",
                subtitle: book.displayTitle
            ) {
                headerCard

                progressSection

                sessionSection

                passageSection

                actionButtons
            }
            .pageTitle("Log Reading")
            .toolbar { SheetDoneButton { dismiss() } }
        }
    }

    private var headerCard: some View {
        ChickenSection("Print Edition") {
            ChickenRow(isLast: true) {
                HStack(alignment: .top, spacing: 14) {
                    BookCover(book: book, style: .tile)
                        .frame(width: 64, height: 96)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(book.displayTitle)
                            .font(.chickenDisplay(19, weight: .bold))
                            .foregroundStyle(palette.text)
                            .lineLimit(2)
                        if let author = book.author, !author.isEmpty {
                            Text(author)
                                .font(.chickenSerif(14, italic: true))
                                .foregroundStyle(palette.muted)
                        }
                        HStack(spacing: 8) {
                            Label("Print", systemImage: "book.closed")
                                .font(.chickenUI(11.5, weight: .semibold))
                                .foregroundStyle(palette.ribbon)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(palette.ribbon.opacity(0.12), in: Capsule())

                            if let isbn = book.isbn, !isbn.isEmpty {
                                Text("ISBN \(isbn)")
                                    .font(.chickenMono(11))
                                    .foregroundStyle(palette.faint)
                            }
                        }
                        if let total = effectiveTotalPages, let current = parsedCurrentPage {
                            Text("Page \(min(current, total)) of \(total) · \(Int((percentValue * 100).rounded()))%")
                                .font(.chickenMono(12, weight: .medium))
                                .foregroundStyle(palette.muted)
                        } else {
                            Text("\(Int((percentValue * 100).rounded()))% complete")
                                .font(.chickenMono(12, weight: .medium))
                                .foregroundStyle(palette.muted)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var progressSection: some View {
        ChickenSection("Progress") {
            ChickenRow {
                HStack(spacing: 12) {
                    Text("Total Pages")
                        .font(.chickenUI(13.5, weight: .medium))
                        .foregroundStyle(palette.muted)
                        .frame(width: 96, alignment: .leading)
                    TextField("Unknown", text: $totalPagesText)
                        .font(.chickenMono(14))
                        .foregroundStyle(palette.text)
                        .textFieldStyle(.plain)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .onChange(of: totalPagesText) { _, _ in
                            syncPercentFromPage()
                        }
                }
            }
            ChickenRow {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Text("Current Page")
                            .font(.chickenUI(13.5, weight: .medium))
                            .foregroundStyle(palette.muted)
                            .frame(width: 96, alignment: .leading)
                        TextField("0", text: $currentPageText)
                            .font(.chickenMono(16, weight: .semibold))
                            .foregroundStyle(palette.text)
                            .textFieldStyle(.plain)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .onChange(of: currentPageText) { _, _ in
                                syncPercentFromPage()
                            }
                        Spacer()
                        HStack(spacing: 6) {
                            pageDeltaButton("-1", delta: -1)
                            pageDeltaButton("+1", delta: 1)
                            pageDeltaButton("+10", delta: 10)
                        }
                    }
                }
            }
            ChickenRow(isLast: true) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Completion")
                            .font(.chickenUI(13.5, weight: .medium))
                            .foregroundStyle(palette.muted)
                        Spacer()
                        Text("\(Int((percentValue * 100).rounded()))%")
                            .font(.chickenMono(14, weight: .semibold))
                            .foregroundStyle(palette.ribbon)
                    }
                    Slider(
                        value: Binding(
                            get: { percentValue },
                            set: { newValue in
                                percentValue = min(max(newValue, 0), 1)
                                if let total = effectiveTotalPages, total > 0 {
                                    let mapped = Int((Double(total) * percentValue).rounded())
                                    currentPageText = String(min(total, max(0, mapped)))
                                }
                            }
                        ),
                        in: 0...1
                    )
                    .tint(palette.ribbon)
                }
            }
        }
    }

    private var sessionSection: some View {
        ChickenSection("Reading Session", footer: "Time added here counts toward your daily goal and reading stats.") {
            ChickenRow {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let totalSeconds = totalSessionSeconds(at: context.date)
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Session Duration")
                                .font(.chickenUI(13.5, weight: .medium))
                                .foregroundStyle(palette.muted)
                            Text(formattedClock(seconds: totalSeconds))
                                .font(.chickenMono(22, weight: .semibold))
                                .foregroundStyle(palette.text)
                        }
                        Spacer()
                        Button {
                            toggleTimer()
                        } label: {
                            Label(timerRunning ? "Pause" : "Start Timer", systemImage: timerRunning ? "pause.fill" : "play.fill")
                                .font(.chickenUI(13, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(timerRunning ? palette.muted : palette.ribbon)
                    }
                }
            }
            ChickenRow(isLast: true) {
                HStack(spacing: 8) {
                    ForEach([15, 30, 45, 60], id: \.self) { mins in
                        Button("+\(mins)m") {
                            addedMinutes += mins
                        }
                        .font(.chickenMono(12.5, weight: .semibold))
                        .buttonStyle(.bordered)
                        .tint(palette.ribbon)
                    }
                    Spacer()
                    if addedMinutes > 0 || accumulatedTimerSeconds > 0 || timerRunning {
                        Button("Reset") {
                            timerRunning = false
                            timerStartedAt = nil
                            accumulatedTimerSeconds = 0
                            addedMinutes = 0
                        }
                        .font(.chickenUI(12.5, weight: .medium))
                        .foregroundStyle(palette.muted)
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var passageSection: some View {
        ChickenSection("Save a Passage (Optional)") {
            ChickenRow {
                TextField("Type or dictate a memorable quote…", text: $quoteText, axis: .vertical)
                    .font(.chickenSerif(14.5))
                    .foregroundStyle(palette.text)
                    .lineLimit(3...6)
                    .textFieldStyle(.plain)
            }
            ChickenRow {
                TextField("Your note (optional)", text: $quoteNote, axis: .vertical)
                    .font(.chickenUI(13.5))
                    .foregroundStyle(palette.text)
                    .lineLimit(1...3)
                    .textFieldStyle(.plain)
            }
            ChickenRow(isLast: true) {
                HStack(spacing: 12) {
                    Text("Highlight Color")
                        .font(.chickenUI(13, weight: .medium))
                        .foregroundStyle(palette.muted)
                    Spacer()
                    HStack(spacing: 10) {
                        ForEach(HighlightColor.allCases) { swatch in
                            Button {
                                quoteColor = swatch
                            } label: {
                                Circle()
                                    .fill(swatch.bar)
                                    .frame(width: 24, height: 24)
                                    .overlay {
                                        if quoteColor == swatch {
                                            Circle()
                                                .strokeBorder(palette.text, lineWidth: 2)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(swatch.label)
                        }
                    }
                }
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            if !book.isFinished {
                Button {
                    saveProgress(markFinished: true)
                } label: {
                    Label("Mark Finished", systemImage: "checkmark.circle")
                        .font(.chickenUI(14, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .tint(palette.ribbon)
            }

            Spacer()

            Button {
                saveProgress(markFinished: false)
            } label: {
                Label("Save Progress", systemImage: "checkmark")
                    .font(.chickenUI(14, weight: .semibold))
            }
            .inkProminentButton()
        }
    }

    private func pageDeltaButton(_ label: String, delta: Int) -> some View {
        Button(label) {
            let current = parsedCurrentPage ?? 0
            let upperBound = effectiveTotalPages ?? Int.max
            let next = min(upperBound, max(0, current + delta))
            currentPageText = String(next)
            syncPercentFromPage()
        }
        .font(.chickenMono(12, weight: .semibold))
        .buttonStyle(.bordered)
        .tint(palette.ribbon)
    }

    private func syncPercentFromPage() {
        guard let total = effectiveTotalPages, total > 0, let page = parsedCurrentPage else { return }
        percentValue = min(max(Double(page) / Double(total), 0), 1)
    }

    private func toggleTimer() {
        let now = Date()
        if timerRunning {
            if let started = timerStartedAt {
                accumulatedTimerSeconds += max(0, now.timeIntervalSince(started))
            }
            timerStartedAt = nil
            timerRunning = false
        } else {
            timerStartedAt = now
            timerRunning = true
        }
    }

    private func formattedClock(seconds: Int) -> String {
        let hrs = seconds / 3600
        let mins = (seconds % 3600) / 60
        let secs = seconds % 60
        if hrs > 0 {
            return String(format: "%d:%02d:%02d", hrs, mins, secs)
        }
        return String(format: "%02d:%02d", mins, secs)
    }

    private func saveProgress(markFinished: Bool) {
        let now = Date()
        if timerRunning, let started = timerStartedAt {
            accumulatedTimerSeconds += max(0, now.timeIntervalSince(started))
            timerStartedAt = nil
            timerRunning = false
        }
        let durationSeconds = totalSessionSeconds(at: now)
        let targetTotal = effectiveTotalPages
        let targetPage: Int? = if markFinished, let targetTotal {
            targetTotal
        } else {
            parsedCurrentPage
        }
        let targetPercent = markFinished ? 1.0 : percentValue
        let cleanQuote = quoteText.trimmingCharacters(in: .whitespacesAndNewlines)

        let justFinished = library.logPhysicalProgress(
            for: book,
            currentPage: targetPage,
            totalPages: targetTotal,
            percent: targetPercent,
            durationSeconds: durationSeconds,
            quoteText: cleanQuote.isEmpty ? nil : cleanQuote,
            quoteNote: quoteNote,
            quoteColor: quoteColor
        )
        dismiss()
        if justFinished {
            onFinished?(book)
        }
    }
}
