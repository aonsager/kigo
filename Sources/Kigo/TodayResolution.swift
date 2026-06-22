import Foundation

// MARK: - ResolvedDay

/// The result of resolving "what is today?" against the loaded `Manifest`.
///
/// Introduced in slice #30 carrying the Kigo (`DailyMapEntry`) only.
/// Extended in slice #31 to carry the current `Ko` (the microseason whose
/// `dateRange` contains the date's `MM-DD` key).
/// Designed for extension in slice #32: add `sekki: Sekki` field
/// without breaking existing callers (see ADR 0007).
///
/// `ResolvedDay` is a value type (struct), Foundation-only, `Sendable`, and `Equatable`.
public struct ResolvedDay: Sendable, Equatable {
    /// The Kigo entry for the resolved date, looked up by absolute `YYYY-MM-DD` day-key.
    public let kigoEntry: DailyMapEntry

    /// The microseason (Kō) whose `dateRange` contains the resolved `MM-DD` day-key.
    /// Containment uses plain string comparison: `dateRange.start ≤ key ≤ dateRange.end`
    /// with no year-wrap logic (see ADR 0008).
    public let ko: Ko

    /// The parent solar term (Sekki) that contains the resolved Kō.
    /// Resolved by matching `ko.sekkiId` to `Sekki.id` in the manifest.
    /// C2 guarantees referential integrity, so a miss is a programming error.
    public let sekki: Sekki
}

// MARK: - TodayResolver

/// A pure, Foundation-only resolver that maps an injected date to a `ResolvedDay`.
///
/// The resolver is a stateless enum namespace (no stored properties) so it is
/// trivially thread-safe and requires no initialisation. Callers pass both the
/// date and the manifest explicitly, keeping the function pure and testable.
///
/// Day-key derivation uses both shared `DayKey` helpers: the absolute `YYYY-MM-DD`
/// key (`DayKey.absolute`) for the Daily Map lookup and the perennial `MM-DD` key
/// (`DayKey.make`) for the Kō `dateRange` containment check (ADR 0016).
///
/// See ADR 0007 for design rationale.
public enum TodayResolver {

    /// Resolves `date` against `manifest` and returns the matching `ResolvedDay`,
    /// or `nil` if the derived day-key is not present in `manifest.dailyMap` or
    /// if no Kō in the manifest contains the derived day-key.
    ///
    /// Ko containment uses plain string comparison (`start ≤ key ≤ end`) with no
    /// year-wrap logic. See ADR 0005 and ADR 0008.
    ///
    /// - Parameters:
    ///   - date: The date to resolve (typically from a `DateProvider`).
    ///   - manifest: The loaded `Manifest` to look up.
    /// - Returns: A `ResolvedDay` carrying the `DailyMapEntry` for the date's absolute
    ///   `YYYY-MM-DD` key and the `Ko` for its perennial `MM-DD` key, or `nil` if either
    ///   lookup fails.
    public static func resolve(date: Date, manifest: Manifest) -> ResolvedDay? {
        // Daily Map is keyed by absolute 2026 dates (ADR 0016); Kō ranges stay
        // perennial MM-DD, so each lookup uses its own key derivation.
        guard let absoluteKey = DayKey.absolute(from: date),
              let perennialKey = DayKey.make(from: date),
              let entry = manifest.dailyMap[absoluteKey],
              let ko = manifest.ko.first(where: { $0.dateRange.start <= perennialKey && perennialKey <= $0.dateRange.end }) else {
            return nil
        }
        guard let sekki = manifest.sekki.first(where: { $0.id == ko.sekkiId }) else {
            preconditionFailure("Manifest referential integrity violation: Ko '\(ko.kanji)' has sekkiId '\(ko.sekkiId)' but no matching Sekki found. C2 guarantees all sekkiId values resolve.")
        }
        return ResolvedDay(kigoEntry: entry, ko: ko, sekki: sekki)
    }
}
