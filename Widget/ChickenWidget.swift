import ChickenKit
import ImageIO
import SwiftUI
import WidgetKit

@main
struct ChickenWidgetBundle: WidgetBundle {
    var body: some Widget {
        ContinueReadingWidget()
    }
}

struct ContinueReadingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.widgetKind, provider: SnapshotProvider()) { entry in
            ContinueReadingView(entry: entry)
                .containerBackground(for: .widget) { WidgetColors(theme: entry.snapshot?.theme).background }
        }
        .configurationDisplayName("Continue Reading")
        .description("The book you're reading and today's reading time.")
        .supportedFamilies(Self.families)
    }

    private static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular]
        #else
        [.systemSmall, .systemMedium]
        #endif
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let cover: CGImage?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(
            date: .now,
            snapshot: WidgetSnapshot(
                currentBook: .init(id: UUID(), title: "The Quiet Room", author: "A. Writer", progress: 0.42, coverTintIndex: 0, hasCover: false),
                secondsToday: 1080,
                dailyGoalMinutes: 30,
                theme: "paper"
            ),
            cover: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        // The app reloads the timeline whenever reading state changes; the
        // midnight refresh resets "today" when the app hasn't been opened.
        let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
        completion(Timeline(entries: [currentEntry()], policy: .after(midnight)))
    }

    private func currentEntry() -> SnapshotEntry {
        let snapshot = WidgetSnapshot.load()
        var cover: CGImage?
        if snapshot?.currentBook?.hasCover == true,
           let url = WidgetSnapshot.coverURL,
           let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            cover = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        return SnapshotEntry(date: .now, snapshot: snapshot, cover: cover)
    }
}

struct ContinueReadingView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var colors: WidgetColors { WidgetColors(theme: entry.snapshot?.theme) }
    private var book: WidgetSnapshot.CurrentBook? { entry.snapshot?.currentBook }

    var body: some View {
        Group {
            if let book {
                switch family {
                case .accessoryRectangular: rectangular(book)
                case .accessoryCircular: circular(book)
                case .systemMedium: medium(book)
                default: small(book)
                }
            } else {
                empty
            }
        }
        .widgetURL(book.map { ChickenLink.book($0.id) } ?? ChickenLink.continueReading)
    }

    private func small(_ book: WidgetSnapshot.CurrentBook) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            cover(book)
                .frame(width: 52, height: 78)
            Spacer(minLength: 0)
            Text(book.title)
                .font(.system(size: 13, weight: .medium, design: .serif))
                .foregroundStyle(colors.text)
                .lineLimit(2)
            progress(book.progress)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func medium(_ book: WidgetSnapshot.CurrentBook) -> some View {
        HStack(spacing: 16) {
            cover(book)
                .frame(width: 84, height: 126)
            VStack(alignment: .leading, spacing: 4) {
                Text("CONTINUE READING")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(colors.muted)
                Text(book.title)
                    .font(.system(size: 17, weight: .medium, design: .serif))
                    .foregroundStyle(colors.text)
                    .lineLimit(2)
                Text(book.author)
                    .font(.system(size: 13, design: .serif).italic())
                    .foregroundStyle(colors.muted)
                    .lineLimit(1)
                Spacer(minLength: 6)
                progress(book.progress)
                if let snapshot = entry.snapshot {
                    Text("\(snapshot.secondsToday / 60) of \(snapshot.dailyGoalMinutes) min today")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(colors.muted)
                }
            }
            Spacer(minLength: 0)
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
            Text("Open a book in Chicken to see it here.")
                .font(.system(size: 12, design: .serif))
                .foregroundStyle(colors.text)
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
                ZStack(alignment: .bottomLeading) {
                    WidgetColors.coverTint(book.coverTintIndex)
                    Text(book.title)
                        .font(.system(size: 8, weight: .medium, design: .serif))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(3)
                        .padding(5)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
    }

    private func progress(_ value: Double) -> some View {
        HStack(spacing: 6) {
            ProgressView(value: value)
                .tint(colors.text)
            Text("\(Int((value * 100).rounded()))%")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(colors.muted)
        }
    }
}

/// The widget's subset of Chicken's reading themes.
struct WidgetColors {
    let background: Color
    let text: Color
    let muted: Color

    init(theme: String?) {
        switch theme {
        case "sepia":
            background = Color(red: 0.937, green: 0.890, blue: 0.800)
            text = Color(red: 0.227, green: 0.165, blue: 0.094)
            muted = Color(red: 0.478, green: 0.353, blue: 0.251)
        case "ink":
            background = Color(red: 0.059, green: 0.059, blue: 0.063)
            text = Color(red: 0.910, green: 0.902, blue: 0.882)
            muted = Color(red: 0.604, green: 0.588, blue: 0.553)
        default:
            background = Color(red: 0.961, green: 0.945, blue: 0.910)
            text = Color(red: 0.122, green: 0.106, blue: 0.086)
            muted = Color(red: 0.420, green: 0.396, blue: 0.357)
        }
    }

    static func coverTint(_ index: Int) -> Color {
        let tints: [Color] = [
            Color(red: 0.122, green: 0.227, blue: 0.302),
            Color(red: 0.420, green: 0.243, blue: 0.227),
            Color(red: 0.176, green: 0.290, blue: 0.165),
            Color(red: 0.102, green: 0.102, blue: 0.102),
            Color(red: 0.227, green: 0.239, blue: 0.251),
            Color(red: 0.722, green: 0.565, blue: 0.184),
        ]
        return tints[((index % tints.count) + tints.count) % tints.count]
    }
}
