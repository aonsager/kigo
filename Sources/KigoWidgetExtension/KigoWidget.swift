@preconcurrency import WidgetKit
import SwiftUI

// MARK: - KigoWidgetProvider
//
// Slice #73: Thin adapter over `WidgetTimelineBuilder`.
//
// Constructs the three production seams:
//   - `SystemDateProvider`          — provides `Date()` for today
//   - `BundledContentSource`        — loads manifest.json from the widget
//                                     extension bundle (bundled in project.yml,
//                                     slice #73 / ADR 0012)
//   - `UserDefaultsEntitlementStore` — reads the shared app-group entitlement
//                                     flag written by `EntitlementProvider`
//
// All resolution and entitlement logic lives in `WidgetTimelineBuilder`; this
// provider is correct by inspection — no logic beyond constructing seams and
// bridging the async builder to WidgetKit's completion-handler callbacks.

struct KigoWidgetProvider: TimelineProvider {

    // MARK: - Placeholder

    func placeholder(in context: Context) -> KigoWidgetEntry {
        // Placeholder shown during widget gallery / loading state.
        // Use a static placeholder entry with known Kigo content.
        KigoWidgetEntry(date: .now,
                        kanji: "蛍",
                        reading: "ほたる",
                        imageId: "placeholder",
                        showsImage: false)
    }

    // MARK: - Snapshot

    func getSnapshot(in context: Context, completion: @escaping (KigoWidgetEntry) -> Void) {
        nonisolated(unsafe) let completion = completion
        nonisolated(unsafe) let context = context
        Task {
            if let entry = await buildEntry() {
                completion(entry)
            } else {
                completion(placeholder(in: context))
            }
        }
    }

    // MARK: - Timeline

    func getTimeline(in context: Context, completion: @escaping (Timeline<KigoWidgetEntry>) -> Void) {
        nonisolated(unsafe) let completion = completion
        Task {
            let entries = await buildTimeline()
            // Reload at the next midnight so the widget flips to the new day's
            // Kigo automatically. The builder places entry[1] at local midnight,
            // making it the natural reload boundary.
            if entries.count >= 2 {
                let policy = TimelineReloadPolicy.after(entries[1].date)
                completion(Timeline(entries: entries, policy: policy))
            } else {
                // Fallback: single entry, reload in 1 hour.
                let fallbackDate = Date(timeIntervalSinceNow: 3600)
                completion(Timeline(entries: entries, policy: .after(fallbackDate)))
            }
        }
    }

    // MARK: - Private helpers

    private func makeBuilder() async -> WidgetTimelineBuilder? {
        let manifest: Manifest
        do {
            manifest = try await BundledContentSource().load()
        } catch {
            return nil
        }
        return WidgetTimelineBuilder(
            dateProvider: SystemDateProvider(),
            manifest: manifest
        )
    }

    private func buildEntry() async -> KigoWidgetEntry? {
        guard let builder = await makeBuilder() else { return nil }
        return builder.buildEntry()
    }

    private func buildTimeline() async -> [KigoWidgetEntry] {
        guard let builder = await makeBuilder() else { return [] }
        return builder.buildTimeline(calendar: .current)
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
        // Drop WidgetKit's default content margins so the image renders
        // edge-to-edge with no canvas border; the text VStack keeps its own
        // `.padding()` for legibility.
        .contentMarginsDisabled()
    }
}

// MARK: - Widget Bundle

@main
struct KigoWidgetBundle: WidgetBundle {
    var body: some Widget {
        KigoWidget()
    }
}
