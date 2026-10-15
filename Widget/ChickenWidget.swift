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
                .font(.custom("Superclarendon-Regular", size: 14))
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
                Text("WHERE YOU LEFT OFF")
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(1.3)
                    .foregroundStyle(colors.ribbon)
                    .widgetAccentable()
                Text(book.title)
                    .font(.custom("Superclarendon-Regular", size: 18))
                    .foregroundStyle(colors.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(book.author)
                    .font(.custom("IowanOldStyle-Italic", size: 13))
                    .foregroundStyle(colors.muted)
                    .lineLimit(1)
                Spacer(minLength: 6)
                progress(book.progress)
                if let snapshot = entry.snapshot {
                    Text("\(snapshot.secondsToday / 60) of \(snapshot.dailyGoalMinutes) min read today")
                        .font(.system(size: 11).monospacedDigit())
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
            Text("Nothing on the go")
                .font(.custom("Superclarendon-Regular", size: 14))
                .foregroundStyle(colors.text)
            Text("Open a book in Chicken and it waits here.")
                .font(.custom("IowanOldStyle-Italic", size: 12))
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
                        .font(.custom("Superclarendon-Regular", size: 9))
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
            // The ribbon: this is the book you're in.
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

/// The widget's subset of Chicken's reading themes (see Theme.swift).
struct WidgetColors {
    let background: Color
    let text: Color
    let muted: Color
    let ribbon: Color

    init(theme: String?) {
        switch theme {
        case "sepia":
            background = .widgetHex(0xEEDFC4)
            text = .widgetHex(0x3B2A1A)
            muted = .widgetHex(0x77593C)
            ribbon = .widgetHex(0xA9642A)
        case "ink":
            background = .widgetHex(0x171413)
            text = .widgetHex(0xF2E6D6)
            muted = .widgetHex(0xA89B8C)
            ribbon = .widgetHex(0xCB8D45)
        default:
            background = .widgetHex(0xF4EEE4)
            text = .widgetHex(0x211D1C)
            muted = .widgetHex(0x6E6259)
            ribbon = .widgetHex(0xB57631)
        }
    }

    /// Same bookcloth as the app's typographic covers (CoverPreset).
    static func coverTint(_ index: Int) -> (cloth: Color, ink: Color) {
        let tints: [(UInt32, UInt32)] = [
            (0x2A2523, 0xE9D9C2), (0x76593F, 0xF2E6D6), (0xC48C44, 0x2A2118), (0x45503A, 0xE6DCC0),
            (0x6E2C27, 0xEFD9BE), (0xE6D9C4, 0x2A2523), (0x2F3E4A, 0xDCCBA8), (0x9A4E2E, 0xF4E3CB),
        ]
        let tint = tints[((index % tints.count) + tints.count) % tints.count]
        return (.widgetHex(tint.0), .widgetHex(tint.1))
    }
}

/// A bookmark ribbon with a swallowtail end.
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
