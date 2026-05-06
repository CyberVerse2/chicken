import SwiftUI
import WidgetKit

struct ReadingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ChickenReadingWidget", provider: Provider()) { _ in
            Text("Chicken")
        }
        .configurationDisplayName("Chicken")
        .description("Recent reading progress.")
    }
}

private struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: .now)], policy: .never))
    }
}

private struct Entry: TimelineEntry {
    let date: Date
}
