import XCTest
@testable import KigoCore

/// DayKey derivation tests — extracted from KigoTests/ResolutionTests when DayKey
/// moved into KigoCore (host-side fast lane; no simulator).
final class DayKeyTests: XCTestCase {

    /// A UTC date for the given 2026 month/day (mirror of ResolutionTests.makeUTCDate).
    private func makeUTCDate(month: Int, day: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
    }

    /// UTC. 2026-07-02 15:30 UTC is 2026-07-03 00:30 JST (UTC+9).
    private func lateNightJSTInstant() -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return utc.date(from: DateComponents(
            year: 2026, month: 7, day: 2, hour: 15, minute: 30))!
    }

    /// `DayKey.make` produces the perennial `MM-DD` key used for Kō range containment.
    func testDayKeyMakeProducesCorrectFormat() {
        let june13 = makeUTCDate(month: 6, day: 13)
        let key = DayKey.make(from: june13, timeZone: DayKey.utcCalendar.timeZone)
        XCTAssertEqual(key, "06-13", "DayKey.make should format date as MM-DD in UTC")
    }

    /// `DayKey.absolute` produces the `YYYY-MM-DD` key used for the daily-map lookup.
    func testDayKeyAbsoluteProducesYYYYMMDD() {
        let june13 = makeUTCDate(month: 6, day: 13)
        let key = DayKey.absolute(from: june13, timeZone: DayKey.utcCalendar.timeZone)
        XCTAssertEqual(key, "2026-06-13", "DayKey.absolute should format date as YYYY-MM-DD in UTC")
    }

    func testDayKeyMakeLeapDay() {
        // Feb 29 in 2024 (a leap year) — DayKey.make is year-independent (perennial MM-DD).
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var comps = DateComponents()
        comps.year = 2024
        comps.month = 2
        comps.day = 29
        comps.hour = 12
        let leapDay = cal.date(from: comps)!

        let key = DayKey.make(from: leapDay, timeZone: DayKey.utcCalendar.timeZone)
        XCTAssertEqual(key, "02-29", "DayKey.make should handle leap day correctly")
    }

    /// ADR 0020: `DayKey` derives the calendar day in the supplied timezone. The same
    /// instant yields the *local* day in JST and the *previous* day in UTC — this is the
    /// off-by-one a JST user saw when production derived "today" in UTC.
    func testDayKeyDerivesDayInProvidedTimeZone() {
        let instant = lateNightJSTInstant()
        let jst = TimeZone(identifier: "Asia/Tokyo")!
        let utc = TimeZone(identifier: "UTC")!

        XCTAssertEqual(DayKey.make(from: instant, timeZone: jst), "07-03",
                       "JST local day is July 3")
        XCTAssertEqual(DayKey.absolute(from: instant, timeZone: jst), "2026-07-03",
                       "JST local absolute day is 2026-07-03")
        XCTAssertEqual(DayKey.make(from: instant, timeZone: utc), "07-02",
                       "The same instant is still July 2 in UTC")
        XCTAssertEqual(DayKey.absolute(from: instant, timeZone: utc), "2026-07-02",
                       "The same instant is still 2026-07-02 in UTC")
    }
}
