import Foundation

// MARK: - WidgetTimelineBuilder
//
// Slice #69: Pure timeline builder for the Kigo widget extension.
//
// Given an injected `DateProvider`, a loaded `Manifest`, and nothing else,
// produces a `KigoWidgetEntry` whose content fields (kanji, reading, imageId)
// match the Manifest's daily-map entry for the injected date.
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

    public init(dateProvider: DateProvider, manifest: Manifest) {
        self.dateProvider = dateProvider
        self.manifest = manifest
    }

    /// Builds a single `KigoWidgetEntry` for the current date from the injected
    /// `DateProvider`, resolving against the injected `Manifest`.
    ///
    /// Returns `nil` if the date's day-key is absent from the manifest or if
    /// the Ko/Sekki lookup fails (impossible for a well-formed bundled manifest,
    /// but possible with minimal test manifests).
    public func buildEntry() -> KigoWidgetEntry? {
        let today = dateProvider.today
        guard let resolved = TodayResolver.resolve(date: today, manifest: manifest) else {
            return nil
        }
        return KigoWidgetEntry(
            date: today,
            kanji: resolved.kigoEntry.kanji,
            reading: resolved.kigoEntry.reading,
            imageId: resolved.kigoEntry.imageId
        )
    }
}
