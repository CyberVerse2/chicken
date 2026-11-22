import ChickenKit
import ImageIO
import SwiftUI
import WidgetKit

@main
struct ChickenWidgetBundle: WidgetBundle {
    var body: some Widget {
        ContinueReadingWidget()
        ReadingGoalWidget()
        ContinueReadingControl()
        #if os(iOS)
        ReadingLiveActivity()
        #endif
    }
}

struct ContinueReadingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.widgetKind, provider: SnapshotProvider(loadsCover: true)) { entry in
            ContinueReadingView(entry: entry)
                .containerBackground(for: .widget) { WidgetColors(theme: entry.snapshot?.theme).background }
        }
        .configurationDisplayName("Continue Reading")
        .description("The book you're reading, and your week of reading.")
        .supportedFamilies(Self.families)
    }

    private static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular]
        #else
        [.systemSmall, .systemMedium, .systemLarge]
        #endif
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let cover: CGImage?
}

struct SnapshotProvider: TimelineProvider {
    let loadsCover: Bool

    init(loadsCover: Bool = true) {
        self.loadsCover = loadsCover
    }

    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(
            date: .now,
            snapshot: WidgetSnapshot(
                currentBook: .init(id: UUID(), title: "The Quiet Room", author: "A. Writer", progress: 0.42, coverTintIndex: 0, hasCover: false),
                secondsToday: 1080,
                dailyGoalMinutes: 30,
                theme: "paper",
                lastSevenDays: [1500, 2400, 0, 1900, 3100, 1200, 1080],
                finishedThisYear: 4,
                annualGoal: 12,
                chapter: "Chapter Three"
            ),
            cover: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: .now)
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? .now.addingTimeInterval(3600)
        completion(Timeline(entries: [currentEntry()], policy: .after(nextMidnight)))
    }

    private func currentEntry() -> SnapshotEntry {
        let snapshot = WidgetSnapshot.load()
        var cover: CGImage?
        if loadsCover,
           snapshot?.currentBook?.hasCover == true,
           let url = WidgetSnapshot.coverURL,
           let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            cover = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        return SnapshotEntry(date: .now, snapshot: snapshot, cover: cover)
    }
}

struct ContinueReadingView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    let entry: SnapshotEntry

    private var colors: WidgetColors { WidgetColors(theme: showsBackground ? entry.snapshot?.theme : "ink") }
    private var book: WidgetSnapshot.CurrentBook? { entry.snapshot?.currentBook }

    var body: some View {
        Group {
            if let book {
                switch family {
                case .accessoryRectangular: rectangular(book)
                case .accessoryCircular: circular(book)
                case .systemMedium: medium(book)
                case .systemLarge: large(book)
                default: small(book)
                }
            } else {
                emptyView
            }
        }
        .widgetURL(book.map { ChickenLink.book($0.id) } ?? ChickenLink.continueReading)
    }

    @ViewBuilder
    private var emptyView: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "book.closed")
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Chicken").font(.headline).widgetAccentable()
                Text("Open a book").font(.caption)
            }
        default:
            empty
        }
    }

    private func small(_ book: WidgetSnapshot.CurrentBook) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                cover(book)
                    .frame(width: 50, height: 75)
                Spacer(minLength: 0)
                Text("\(Int((book.progress * 100).rounded()))%")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(colors.ribbon)
                    .widgetAccentable()
            }
            Spacer(minLength: 0)
            Text(book.title)
                .font(.system(size: 14, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(colors.text)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            progress(book.progress)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func medium(_ book: WidgetSnapshot.CurrentBook) -> some View {
        HStack(spacing: 16) {
            cover(book)
                .frame(width: 78, height: 117)
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.system(size: 17.5, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(colors.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(book.author)
                    .font(.system(size: 12.5))
                    .foregroundStyle(colors.muted)
                    .lineLimit(1)
                Spacer(minLength: 6)
                progress(book.progress)
                if let snapshot = entry.snapshot {
                    Text("\(snapshot.secondsToday(on: entry.date) / 60) of \(snapshot.dailyGoalMinutes) min read today")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(colors.muted)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func large(_ book: WidgetSnapshot.CurrentBook) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                cover(book)
                    .frame(width: 84, height: 126)
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title)
                        .font(.system(size: 19.5, weight: .semibold))
                        .tracking(-0.4)
                        .foregroundStyle(colors.text)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                    Text(book.author)
                        .font(.system(size: 13.5))
                        .foregroundStyle(colors.muted)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let chapter = entry.snapshot?.chapter, !chapter.isEmpty {
                        Text(chapter)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(colors.text.opacity(0.8))
                            .lineLimit(1)
                    }
                    HStack(spacing: 8) {
                        progress(book.progress)
                        Text("\(Int((book.progress * 100).rounded()))%")
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(colors.ribbon)
                            .widgetAccentable()
                    }
                }
                .frame(height: 126, alignment: .top)
            }

            Spacer(minLength: 14)
            Rectangle().fill(colors.text.opacity(0.1)).frame(height: 1)
            Spacer(minLength: 12)

            if let snapshot = entry.snapshot {
                WeekChart(snapshot: snapshot, date: entry.date, colors: colors)
                Spacer(minLength: 10)
                if let goal = snapshot.annualGoal, goal > 0 {
                    Text("\(snapshot.finishedThisYear ?? 0) of \(goal) books finished this year")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(colors.muted)
                }
            }
        }
    }

    private func rectangular(_ book: WidgetSnapshot.CurrentBook) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(book.title)
                .font(.headline)
                .widgetAccentable()
                .lineLimit(1)
            Text(book.author).font(.caption).lineLimit(1)
            Gauge(value: book.progress) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
        }
    }

    private func circular(_ book: WidgetSnapshot.CurrentBook) -> some View {
        Gauge(value: book.progress) {
            Image(systemName: "book")
        } currentValueLabel: {
            Text("\(Int((book.progress * 100).rounded()))")
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "books.vertical")
                .font(.title2)
                .foregroundStyle(colors.muted)
            Spacer(minLength: 0)
            Text("Nothing on the go")
                .font(.system(size: 14, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(colors.text)
            Text("Open a book in Chicken and it waits here.")
                .font(.system(size: 12))
                .foregroundStyle(colors.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func cover(_ book: WidgetSnapshot.CurrentBook) -> some View {
        Group {
            if let image = entry.cover {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .widgetAccentedRenderingMode(.desaturated)
                    .aspectRatio(contentMode: .fill)
            } else {
                let tint = WidgetColors.coverTint(book.coverTintIndex)
                ZStack {
                    tint.cloth
                    Text(book.title)
                        .font(.system(size: 9.5, weight: .semibold, design: .serif))
                        .foregroundStyle(tint.ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .minimumScaleFactor(0.7)
                        .padding(6)
                }
            }
        }
        .overlay(alignment: .leading) {
            LinearGradient(colors: [.black.opacity(0.22), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 3, x: 1, y: 2)
        .overlay(alignment: .bottomTrailing) {
            WidgetRibbon()
                .fill(colors.ribbon)
                .frame(width: 6, height: 13)
                .offset(x: -10, y: 9)
                .widgetAccentable()
        }
    }

    private func progress(_ value: Double) -> some View {
        HStack(spacing: 6) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(colors.text.opacity(0.12))
                    Capsule().fill(colors.ribbon)
                        .frame(width: geometry.size.width * min(max(value, 0), 1))
                        .widgetAccentable()
                }
            }
            .frame(height: 3)
        }
    }
}

struct WidgetColors {
    let background: Color
    let text: Color
    let muted: Color
    let ribbon: Color

    init(theme: String?) {
        let tokens = SharedThemeTokens.forName(theme)
        background = .widgetHex(tokens.backgroundHex)
        text = .widgetHex(tokens.textHex)
        muted = .widgetHex(tokens.mutedHex)
        ribbon = .widgetHex(tokens.ribbonHex)
    }

    static func coverTint(_ index: Int) -> (cloth: Color, ink: Color) {
        let preset = SharedCoverCloth.preset(for: index)
        return (.widgetHex(preset.clothHex), .widgetHex(preset.inkHex))
    }
}

struct WidgetRibbon: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.width * 0.8))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private extension Color {
    static func widgetHex(_ value: UInt32) -> Color {
        Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
