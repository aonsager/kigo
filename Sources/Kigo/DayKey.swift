import Foundation

// MARK: - DayKey

/// Derives a perennial `MM-DD` day key from a `Date` using UTC.
///
/// This is the single, canonical implementation of the `MM-DD` derivation used
/// throughout the Kigo module. Both `ContentStore.todayEntry()` and `TodayResolver`
/// call this helper — there is intentionally only one copy of the UTC calendar and
/// the `String(format:)` formatting logic.
///
/// UTC is chosen for determinism (ADR 0006): the same `Date` value always produces
/// the same day-key regardless of the caller's local timezone or test-runner timezone.
public enum DayKey {

    /// UTC Gregorian calendar shared across all callers.
    ///
    /// Using a `static let` ensures the calendar is initialised once and reused;
    /// `Calendar` construction is non-trivial so this avoids repeated allocation.
    ///
    /// Exposed as `public` so that `launchDateProvider(environment:)` (and any
    /// future callers outside this file) can parse dates using the same canonical
    /// UTC calendar that `DayKey.make(from:)` uses for key derivation —
    /// satisfying acceptance criterion #4 (one shared UTC calendar, no duplication).
    public static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    /// Derives the perennial `MM-DD` key for `date` using UTC.
    ///
    /// Returns `nil` if the calendar cannot extract month and day components
    /// from `date` (in practice this should never happen for well-formed `Date` values).
    public static func make(from date: Date) -> String? {
        let comps = utcCalendar.dateComponents([.month, .day], from: date)
        guard let month = comps.month, let day = comps.day else { return nil }
        return String(format: "%02d-%02d", month, day)
    }

    /// Derives the absolute `YYYY-MM-DD` key for `date` using UTC.
    ///
    /// This is the daily-map lookup key after the ADR 0016 migration: the Daily Map
    /// is keyed by absolute 2026 dates, so a remote update (C21) can override a
    /// specific calendar day of a specific year. The perennial `MM-DD` key from
    /// `make(from:)` remains the key for the year-independent Kō `dateRange` check.
    ///
    /// Returns `nil` if the calendar cannot extract year, month, and day components.
    public static func absolute(from date: Date) -> String? {
        let comps = utcCalendar.dateComponents([.year, .month, .day], from: date)
        guard let year = comps.year, let month = comps.month, let day = comps.day else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
