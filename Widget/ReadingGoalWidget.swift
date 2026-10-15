import ChickenKit
import SwiftUI
import WidgetKit

/// Today's minutes against your daily goal. Made for StandBy, where it sits
/// beside the book you're reading on a charging phone, and for the Lock
/// Screen.
struct ReadingGoalWidget: Widget {
    static let kind = "ChickenReadingGoal"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            ReadingGoalView(entry: entry)
                .containerBackground(for: .widget) { WidgetColors(theme: entry.snapshot?.theme).background }
        }
        .configurationDisplayName("Reading Goal")
        .description("Today's reading against your daily goal, and the week so far.")
        .supportedFamilies(Self.families)
    }

    private static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline]
        #else
        [.systemSmall, .systemMedium]
        #endif
    }
}

struct ReadingGoalView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    let entry: SnapshotEntry

    private var colors: WidgetColors { WidgetColors(theme: showsBackground ? entry.snapshot?.theme : "ink") }
    private var minutes: Int { (entry.snapshot?.secondsToday(on: entry.date) ?? 0) / 60 }
    private var goal: Int { entry.snapshot?.dailyGoalMinutes ?? 0 }
    private var fraction: Double { goal > 0 ? min(1, Double(minutes) / Double(goal)) : 0 }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                Gauge(value: fraction) {
                    Image(systemName: "book.pages")
                } currentValueLabel: {
                    Text("\(minutes)")
                }
                .gaugeStyle(.accessoryCircularCapacity)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text(fraction >= 1 ? "Goal done" : "Reading today")
                        .font(.headline)
                        .widgetAccentable()
                    Text("\(minutes) of \(goal) min")
                        .font(.caption.monospacedDigit())
                    Gauge(value: fraction) { EmptyView() }
                        .gaugeStyle(.accessoryLinearCapacity)
                }
            case .accessoryInline:
                Text("\(minutes) of \(goal) min read")
            case .systemMedium:
                medium
            default:
                ring(size: nil)
            }
        }
        .widgetURL(ChickenLink.continueReading)
    }

    private var medium: some View {
        HStack(spacing: 20) {
            ring(size: 112)
            if let snapshot = entry.snapshot {
                WeekChart(snapshot: snapshot, date: entry.date, colors: colors)
            }
        }
    }

    /// The ring fills to the goal; the number in it is today's minutes.
    private func ring(size: CGFloat?) -> some View {
        ZStack {
            Circle()
                .stroke(colors.text.opacity(0.1), lineWidth: 9)
            Circle()
                .trim(from: 0, to: max(fraction, minutes > 0 ? 0.03 : 0))
                .stroke(colors.ribbon, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
            VStack(spacing: 0) {
                Text("\(minutes)")
                    .font(.custom("Superclarendon-Regular", size: 34))
                    .foregroundStyle(colors.text)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(fraction >= 1 ? "goal done" : "of \(goal) min")
                    .font(.custom("IowanOldStyle-Italic", size: 12))
                    .foregroundStyle(colors.muted)
            }
            .monospacedDigit()
            .padding(.horizontal, 14)
        }
        .padding(4.5)
        .frame(width: size, height: size)
        .frame(maxWidth: size == nil ? .infinity : nil, maxHeight: size == nil ? .infinity : nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(minutes) of \(goal) minutes read today")
    }
}

/// Seven bars, today's in the ribbon colour, with the daily goal as a
/// dashed line so a good day reads at a glance.
struct WeekChart: View {
    let snapshot: WidgetSnapshot
    let date: Date
    let colors: WidgetColors

    private var minutes: [Int] { snapshot.week(endingOn: date).map { $0 / 60 } }
    private var goal: Int { snapshot.dailyGoalMinutes }

    private var weekdays: [String] {
        let calendar = Calendar.current
        return (0..<7).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: date) ?? date
            return day.formatted(.dateTime.weekday(.narrow))
        }
    }

    private var total: String {
        let sum = minutes.reduce(0, +)
        return sum >= 60 ? "\(sum / 60)h \(sum % 60)m" : "\(sum) min"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week")
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .foregroundStyle(colors.muted)
                Spacer(minLength: 4)
                Text(total)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(colors.muted)
            }

            GeometryReader { geometry in
                let scale = CGFloat(max(goal, minutes.max() ?? 0, 1))
                let height = geometry.size.height
                ZStack(alignment: .bottom) {
                    if goal > 0 {
                        Path { path in
                            let y = height - height * CGFloat(goal) / scale
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                        }
                        .stroke(colors.text.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    }
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(Array(minutes.enumerated()), id: \.offset) { index, value in
                            let isToday = index == minutes.count - 1
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(isToday ? colors.ribbon : colors.text.opacity(value >= goal && goal > 0 ? 0.55 : 0.3))
                                .frame(maxWidth: 16)
                                .frame(height: max(3, height * CGFloat(value) / scale))
                                .frame(maxWidth: .infinity)
                                .widgetAccentable(isToday)
                        }
                    }
                }
            }

            HStack(spacing: 0) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { index, letter in
                    Text(letter)
                        .font(.system(size: 10, weight: index == 6 ? .bold : .regular))
                        .foregroundStyle(index == 6 ? colors.text : colors.muted)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(total) read this week")
    }
}
