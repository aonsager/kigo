import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct KigoWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> KigoWidgetEntry {
        KigoWidgetEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (KigoWidgetEntry) -> Void) {
        completion(KigoWidgetEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KigoWidgetEntry>) -> Void) {
        completion(Timeline(entries: [KigoWidgetEntry(date: .now)], policy: .never))
    }
}

// MARK: - Widget View

struct KigoWidgetView: View {
    let entry: KigoWidgetEntry

    var body: some View {
        Text("Kigo")
            .containerBackground(.background, for: .widget)
    }
}

// MARK: - Widget

struct KigoWidget: Widget {
    let kind = "KigoWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KigoWidgetProvider()) { entry in
            KigoWidgetView(entry: entry)
        }
        .configurationDisplayName("Kigo")
        .description("Today's seasonal word.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Widget Bundle

@main
struct KigoWidgetBundle: WidgetBundle {
    var body: some Widget {
        KigoWidget()
    }
}
