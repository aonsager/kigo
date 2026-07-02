import Foundation

// MARK: - DayKey

/// Derives a perennial `MM-DD` day key from a `Date` using UTC.
///
/// This is the single, canonical implementation of the `MM-DD` derivation used
/// throughout the Kigo module. Both `ContentStore.todayEntry()` and `TodayResolver`
/// call this helper — there is intentionally only one copy of the UTC calendar and
/// the `String(format:)` formatting logic.
///
/// The day-key is derived in a caller-supplied `timeZone` (default: the device's
/// local zone, `.current`). ADR 0020 supersedes ADR 0006's UTC-in-production choice:
/// a wall-clock instant (`Date()`) must be bucketed into the *user's local* calendar
/// day, or a user east/west of UTC sees the wrong day near the day boundary (a JST
/// user, UTC+9, saw yesterday's Kigo every morning). The `timeZone` seam keeps this
/// injectable so tests remain deterministic by pinning an explicit zone rather than
/// depending on the test-runner's zone. UTC is still used for round-tripping fixed
/// `YYYY-MM-DD` content strings (see `launchDateProvider(environment:)`), which pass
/// `utcCalendar.timeZone` explicitly.
///
/// The calendar is always `.gregorian`: only the *timezone* varies. Deliberately not
/// `Calendar.current`, which would honor the user's calendar *system* (e.g. Japanese
/// or Buddhist) and corrupt the Gregorian `MM-DD` keys the content is keyed by.
public enum DayKey {

    /// UTC Gregorian calendar shared across all callers.
    ///
    /// Using a `static let` ensures the calendar is initialised once and reused;
    /// `Calendar` construction is non-trivial so this avoids repeated allocation.
    ///
    /// Exposed as `public` so that `launchDateProvider(environment:)` (and any
    /// future callers outside this file) can parse dates using the same canonical
    /// UTC calendar, and pass `utcCalendar.timeZone` to `make`/`absolute` so the
    /// derived key matches the UTC-parsed date (one shared UTC calendar, no duplication).
    public static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    /// A Gregorian calendar pinned to `timeZone`. Reuses the cached `utcCalendar`
    /// when UTC is requested; otherwise constructs a fresh Gregorian calendar.
    private static func calendar(for timeZone: TimeZone) -> Calendar {
        if timeZone == utcCalendar.timeZone { return utcCalendar }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }

    /// Derives the perennial `MM-DD` key for `date` in `timeZone` (default: local).
    ///
    /// Returns `nil` if the calendar cannot extract month and day components
    /// from `date` (in practice this should never happen for well-formed `Date` values).
    public static func make(from date: Date, timeZone: TimeZone = .current) -> String? {
        let comps = calendar(for: timeZone).dateComponents([.month, .day], from: date)
        guard let month = comps.month, let day = comps.day else { return nil }
        return String(format: "%02d-%02d", month, day)
    }

    /// Derives the absolute `YYYY-MM-DD` key for `date` in `timeZone` (default: local).
    ///
    /// This is the daily-map lookup key after the ADR 0016 migration: the Daily Map
    /// is keyed by absolute 2026 dates, so a remote update (C21) can override a
    /// specific calendar day of a specific year. The perennial `MM-DD` key from
    /// `make(from:)` remains the key for the year-independent Kō `dateRange` check.
    ///
    /// Returns `nil` if the calendar cannot extract year, month, and day components.
    public static func absolute(from date: Date, timeZone: TimeZone = .current) -> String? {
        let comps = calendar(for: timeZone).dateComponents([.year, .month, .day], from: date)
        guard let year = comps.year, let month = comps.month, let day = comps.day else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
