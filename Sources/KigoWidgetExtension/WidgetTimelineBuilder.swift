import Foundation

// MARK: - WidgetTimelineBuilder
//
// Slice #69: Pure timeline builder for the Kigo widget extension.
//
// Given an injected `DateProvider`, a loaded `Manifest`, and nothing else,
// produces a `KigoWidgetEntry` whose content fields (kanji, reading, imageId)
// match the Manifest's daily-map entry for the injected date.
//
// Slice #70: Extended with `buildTimeline(calendar:)` to return a two-entry
// ordered timeline:
//   - Entry 0: the current date's Kigo (same as `buildEntry()`).
//   - Entry 1: dated at the next local midnight (per the injected calendar),
//              resolving to the next day's Kigo via `TodayResolver`.
//
// The rollover boundary is computed using the caller-supplied `Calendar` so
// that tests can inject a UTC calendar for full determinism (no dependency on
// the test-runner's local timezone). In production, pass `Calendar.current`.
// See ADR 0010 for the UTC-vs-local-midnight design decision.
//
// Slice #71: Added injected `EntitlementSharedStore` to derive `showsImage` on
// each built entry. `buildEntry()` and `buildTimeline(calendar:)` are now `async`
// so they can read `isActive` from the store. The entitlement flag is read once
// at the top of each build call and applied to all entries in that call.
// In production the store is a `UserDefaultsEntitlementStore` backed by
// app-group UserDefaults; tests inject an in-memory actor fake (no StoreKit).
// See ADR 0011 for the Foundation-only factoring decision.
//
// Resolution is delegated entirely to `TodayResolver` / `DayKey` — there is
// no reimplementation of the day-key or Ko/Sekki lookup logic here.
//
// This type is Foundation-only and has no WidgetKit dependency, making it
// directly unit-testable from `KigoWidgetTests` without importing SwiftUI or
// WidgetKit.
public struct WidgetTimelineBuilder: Sendable {

    private let dateProvider: DateProvider
    private let manifest: Manifest
    private let entitlementStore: EntitlementSharedStore

    public init(
        dateProvider: DateProvider,
        manifest: Manifest,
        entitlementStore: EntitlementSharedStore = UserDefaultsEntitlementStore()
    ) {
        self.dateProvider = dateProvider
        self.manifest = manifest
        self.entitlementStore = entitlementStore
    }

    /// Builds a single `KigoWidgetEntry` for the current date from the injected
    /// `DateProvider`, resolving against the injected `Manifest`.
    ///
    /// `showsImage` on the returned entry reflects the current value of the injected
    /// `EntitlementSharedStore.isActive` — never a hardcoded constant.
    ///
    /// Returns `nil` if the date's day-key is absent from the manifest or if
    /// the Ko/Sekki lookup fails (impossible for a well-formed bundled manifest,
    /// but possible with minimal test manifests).
    public func buildEntry() async -> KigoWidgetEntry? {
        let today = dateProvider.today
        let entitled = await entitlementStore.isActive
        guard let resolved = TodayResolver.resolve(date: today, manifest: manifest) else {
            return nil
        }
        return KigoWidgetEntry(
            date: today,
            kanji: resolved.kigoEntry.kanji,
            reading: resolved.kigoEntry.reading.ja,
            imageId: resolved.kigoEntry.imageId,
            showsImage: entitled
        )
    }

    /// Builds a two-entry ordered timeline for the Kigo widget.
    ///
    /// - Parameter calendar: The calendar used to compute the next local midnight.
    ///   Pass `Calendar.current` in production for the device's local timezone.
    ///   Inject a UTC `Calendar` in tests for full determinism regardless of the
    ///   test-runner's timezone. See ADR 0010.
    ///
    /// `showsImage` is derived from the injected `EntitlementSharedStore.isActive` and
    /// applied uniformly to all entries in the timeline (the entitlement flag is read
    /// once at the start of the build call).
    ///
    /// Returns an array of exactly 2 `KigoWidgetEntry` values:
    ///   - Index 0: current date entry (same as `buildEntry()`).
    ///   - Index 1: next local midnight entry (next day's Kigo, resolved via `TodayResolver`).
    ///
    /// If either resolution fails (missing manifest entry), the corresponding entry
    /// is included with nil content fields (unresolved placeholder). This preserves
    /// the two-entry contract so WidgetKit always has a rollover timestamp.
    public func buildTimeline(calendar: Calendar = .current) async -> [KigoWidgetEntry] {
        let today = dateProvider.today
        let entitled = await entitlementStore.isActive

        // Entry 0: current date
        let firstEntry: KigoWidgetEntry
        if let resolved = TodayResolver.resolve(date: today, manifest: manifest) {
            firstEntry = KigoWidgetEntry(
                date: today,
                kanji: resolved.kigoEntry.kanji,
                reading: resolved.kigoEntry.reading.ja,
                imageId: resolved.kigoEntry.imageId,
                showsImage: entitled
            )
        } else {
            firstEntry = KigoWidgetEntry(date: today)
        }

        // Entry 1: next local midnight
        // `startOfDay` on `today + 1 day` gives the start of the next calendar day
        // in the injected calendar's timezone — i.e. the next local midnight.
        let tomorrowDate = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let nextMidnight = calendar.startOfDay(for: tomorrowDate)

        let secondEntry: KigoWidgetEntry
        if let resolved = TodayResolver.resolve(date: nextMidnight, manifest: manifest) {
            secondEntry = KigoWidgetEntry(
                date: nextMidnight,
                kanji: resolved.kigoEntry.kanji,
                reading: resolved.kigoEntry.reading.ja,
                imageId: resolved.kigoEntry.imageId,
                showsImage: entitled
            )
        } else {
            secondEntry = KigoWidgetEntry(date: nextMidnight)
        }

        return [firstEntry, secondEntry]
    }
}
