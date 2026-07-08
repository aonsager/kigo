import Foundation

// MARK: - launchDateProvider

/// Reads the `KIGO_FAKE_DATE` launch-environment variable and returns a
/// `DateProvider` that is pinned to that date (as a `FixedDateProvider`),
/// or falls back to `SystemDateProvider` when the variable is absent or
/// cannot be parsed.
///
/// The string must be in `YYYY-MM-DD` format. Parsing uses `DayKey.utcCalendar`
/// — the shared UTC Gregorian calendar — so acceptance criterion #4 holds:
/// the same UTC calendar governs both the parsed date and the day-key derivation
/// that consumes it.
///
/// This factory is a pure function (aside from `ProcessInfo` in production use):
/// it takes a plain `[String: String]` dictionary so unit tests can exercise all
/// three branches (valid, absent, malformed) without launching the app.
///
/// - Parameter environment: The launch-environment dictionary, typically
///   `ProcessInfo.processInfo.environment` at the app root.
/// - Returns: A `FixedDateProvider` for a valid `KIGO_FAKE_DATE`, or
///   `SystemDateProvider` otherwise.
public func launchDateProvider(environment: [String: String]) -> any DateProvider {
    #if DEBUG
    // Test-only seam: honour KIGO_FAKE_DATE in DEBUG builds only, so the fake
    // date-injection path is never compiled into a Release binary (H1).
    if let rawValue = environment["KIGO_FAKE_DATE"],
       let date = parseYYYYMMDD(rawValue) {
        return FixedDateProvider(date: date)
    }
    #endif
    return SystemDateProvider()
}

#if DEBUG

// MARK: - Private (DEBUG-only test seam)

/// Parses a `YYYY-MM-DD` string using `DayKey.utcCalendar`.
///
/// Returns `nil` if the string is not exactly three dash-separated integer
/// components, or if the component values are out of valid range (month 1-12,
/// day 1-31), or if the resulting `DateComponents` do not form a valid date
/// in the UTC calendar (e.g. April 31).
///
/// The range check is intentionally strict: `Calendar.date(from:)` silently
/// overflows out-of-range values (month 13 → January of the next year), so
/// we guard before calling it.
private func parseYYYYMMDD(_ string: String) -> Date? {
    let parts = string.split(separator: "-", maxSplits: 2)
    guard parts.count == 3,
          let year  = Int(parts[0]),
          let month = Int(parts[1]),
          let day   = Int(parts[2]),
          (1...12).contains(month),
          (1...31).contains(day) else {
        return nil
    }

    var comps = DateComponents()
    comps.year  = year
    comps.month = month
    comps.day   = day
    comps.hour  = 12   // noon UTC — avoids any midnight/DST ambiguity

    // Use DayKey's canonical UTC calendar so the resulting Date maps to the
    // exact same MM-DD key that DayKey.make(from:) will later derive.
    // Passing an invalid combination (e.g. Feb 31) still returns nil here
    // because Calendar.date(from:) only accepts valid dates when components
    // are in-range.
    let date = DayKey.utcCalendar.date(from: comps)

    // Verify round-trip: the derived MM-DD key must match the input month/day.
    // This catches Calendar silent overflow for values that pass range checks
    // but are still invalid (e.g. Feb 30 rolls into March). The round-trip must
    // re-derive in UTC to match the UTC-parsed date above — `DayKey.make` now
    // defaults to the local zone (ADR 0020), so pass UTC explicitly here.
    guard let date,
          let derived = DayKey.make(from: date, timeZone: DayKey.utcCalendar.timeZone),
          derived == String(format: "%02d-%02d", month, day) else {
        return nil
    }
    return date
}

#endif
