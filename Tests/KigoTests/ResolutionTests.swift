import XCTest
@testable import Kigo

// MARK: - ResolutionTests

/// Tests for `TodayResolution` resolver (slice #30, amended for C2/ADR 0016).
///
/// The resolver takes an injected `DateProvider` and a loaded `Manifest`, looks up the
/// Kigo by the **absolute `2026-MM-DD`** day-key (`DayKey.absolute`) and the current Kō
/// by the **perennial `MM-DD`** range (`DayKey.make`), and returns a `ResolvedDay`.
///
/// All tests use `XCTest` and `@testable import Kigo` — no SwiftUI import.
final class ResolutionTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a UTC `Date` in 2026 for the given month and day. The year matters now:
    /// the daily map is keyed by absolute `2026-MM-DD` after the ADR 0016 migration.
    private func makeUTCDate(year: Int = 2026, month: Int, day: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        return cal.date(from: comps)!
    }

    /// Loads the bundled manifest from the test host app bundle.
    private func loadBundledManifest() throws -> Manifest {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "manifest", withExtension: "json"),
            "manifest.json must be bundled in the Kigo app target"
        )
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    // MARK: - AC1 & AC2: Resolver returns the correct DailyMapEntry for a fixed 2026 date

    /// AC1 + AC2: Injecting 2026-06-13 returns the same `DailyMapEntry` that a direct
    /// `dailyMap["2026-06-13"]` lookup yields, and the resolved entry's `description.ja`
    /// carries the absolute date-stamp instrumentation.
    func testResolverReturnsBundledManifestEntryForFixedDate() throws {
        let manifest = try loadBundledManifest()
        let dateProvider = FixedDateProvider(date: makeUTCDate(month: 6, day: 13))

        let resolved = TodayResolver.resolve(date: dateProvider.today, manifest: manifest)

        let expectedEntry = try XCTUnwrap(
            manifest.dailyMap["2026-06-13"],
            "Bundled manifest must have a '2026-06-13' entry"
        )
        XCTAssertNotNil(resolved, "Resolver must return a non-nil ResolvedDay for a known date")
        XCTAssertEqual(
            resolved?.kigoEntry,
            expectedEntry,
            "Resolver must return the same DailyMapEntry as a direct dailyMap['2026-06-13'] lookup"
        )
        XCTAssertTrue(
            resolved?.kigoEntry.description.ja.contains("2026-06-13") ?? false,
            "Resolved description.ja must contain its absolute date stamp '2026-06-13'"
        )
    }

    /// Verifies that multiple different injected 2026 dates each resolve to the correct
    /// DailyMapEntry with the matching date stamp.
    func testResolverReturnsCorrectEntryAcrossMultipleDates() throws {
        let manifest = try loadBundledManifest()

        let testCases: [(month: Int, day: Int)] = [
            (1, 1),    // New Year
            (6, 13),   // mid-year
            (12, 31),  // last day of year
        ]

        for (month, day) in testCases {
            let date = makeUTCDate(month: month, day: day)
            let key = String(format: "2026-%02d-%02d", month, day)
            let expectedEntry = try XCTUnwrap(
                manifest.dailyMap[key],
                "Bundled manifest must have a '\(key)' entry"
            )

            let resolved = TodayResolver.resolve(date: date, manifest: manifest)

            XCTAssertNotNil(resolved, "Resolver must return non-nil for '\(key)'")
            XCTAssertEqual(
                resolved?.kigoEntry,
                expectedEntry,
                "Resolver for '\(key)' must match direct dailyMap lookup"
            )
            XCTAssertTrue(
                resolved?.kigoEntry.description.ja.contains(key) ?? false,
                "Resolved description.ja for '\(key)' must contain its date stamp"
            )
        }
    }

    // MARK: - AC3: Day-key derivation (compile-time + format)

    /// `DayKey.make` produces the perennial `MM-DD` key used for Kō range containment.
    func testDayKeyMakeProducesCorrectFormat() {
        let june13 = makeUTCDate(month: 6, day: 13)
        let key = DayKey.make(from: june13)
        XCTAssertEqual(key, "06-13", "DayKey.make should format date as MM-DD in UTC")
    }

    /// `DayKey.absolute` produces the `YYYY-MM-DD` key used for the daily-map lookup.
    func testDayKeyAbsoluteProducesYYYYMMDD() {
        let june13 = makeUTCDate(month: 6, day: 13)
        let key = DayKey.absolute(from: june13)
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

        let key = DayKey.make(from: leapDay)
        XCTAssertEqual(key, "02-29", "DayKey.make should handle leap day correctly")
    }

    // MARK: - AC4: Resolver is pure / Foundation-only (enforced by no SwiftUI import above)

    /// AC4: Verified at compile time — this file and TodayResolution.swift import only Foundation.
    func testResolverIsStateless() throws {
        let manifest = try loadBundledManifest()
        let date = makeUTCDate(month: 6, day: 13)

        let result1 = TodayResolver.resolve(date: date, manifest: manifest)
        let result2 = TodayResolver.resolve(date: date, manifest: manifest)

        XCTAssertEqual(result1?.kigoEntry, result2?.kigoEntry,
            "Resolver must be deterministic — same inputs must yield equal outputs")
    }

    // MARK: - Edge: unknown key / out-of-range date

    /// If the manifest has no entry for the derived key, the resolver returns nil.
    func testResolverReturnsNilForUnknownKey() {
        let emptyManifest = Manifest(
            schemaVersion: "1.0",
            version: 1,
            dailyMap: [:],
            ko: [],
            sekki: []
        )
        let date = makeUTCDate(month: 6, day: 13)
        let resolved = TodayResolver.resolve(date: date, manifest: emptyManifest)
        XCTAssertNil(resolved, "Resolver must return nil when manifest has no entry for the derived key")
    }

    /// An out-of-range date (2027-01-01, with no Daily-Map entry) resolves to nil — the
    /// "content unavailable" path (no entry, no thrown error). The dataset is 2026-only.
    func testResolverReturnsNilForOutOfRangeYear() throws {
        let manifest = try loadBundledManifest()
        let date = makeUTCDate(year: 2027, month: 1, day: 1)
        let resolved = TodayResolver.resolve(date: date, manifest: manifest)
        XCTAssertNil(resolved, "Resolver must return nil for a 2027 date absent from the 2026 daily map")
    }

    // MARK: - AC1 & AC2 (slice #31): ResolvedDay carries the current Kō per season

    /// Winter (January): 2026-01-07 falls in 芹乃栄 (perennial 01-05 – 01-09).
    func testKoResolvedForWinterDate() throws {
        let manifest = try loadBundledManifest()
        let date = makeUTCDate(month: 1, day: 7)

        let resolved = try XCTUnwrap(
            TodayResolver.resolve(date: date, manifest: manifest),
            "Resolver must return a non-nil ResolvedDay for 2026-01-07"
        )

        XCTAssertEqual(resolved.ko.kanji, "芹乃栄", "01-07 must resolve to Ko kanji 芹乃栄")
        XCTAssertEqual(resolved.ko.reading.ja, "せりすなわちさかう", "01-07 must resolve to Ko reading.ja せりすなわちさかう")
    }

    /// Spring (April): 2026-04-07 falls in 玄鳥至 (perennial 04-05 – 04-09).
    func testKoResolvedForSpringDate() throws {
        let manifest = try loadBundledManifest()
        let date = makeUTCDate(month: 4, day: 7)

        let resolved = try XCTUnwrap(
            TodayResolver.resolve(date: date, manifest: manifest),
            "Resolver must return a non-nil ResolvedDay for 2026-04-07"
        )

        XCTAssertEqual(resolved.ko.kanji, "玄鳥至", "04-07 must resolve to Ko kanji 玄鳥至")
        XCTAssertEqual(resolved.ko.reading.ja, "つばめきたる", "04-07 must resolve to Ko reading.ja つばめきたる")
    }

    /// Summer (July): 2026-07-09 falls in 温風至 (perennial 07-07 – 07-11).
    func testKoResolvedForSummerDate() throws {
        let manifest = try loadBundledManifest()
        let date = makeUTCDate(month: 7, day: 9)

        let resolved = try XCTUnwrap(
            TodayResolver.resolve(date: date, manifest: manifest),
            "Resolver must return a non-nil ResolvedDay for 2026-07-09"
        )

        XCTAssertEqual(resolved.ko.kanji, "温風至", "07-09 must resolve to Ko kanji 温風至")
        XCTAssertEqual(resolved.ko.reading.ja, "あつかぜいたる", "07-09 must resolve to Ko reading.ja あつかぜいたる")
    }

    /// Autumn (September): 2026-09-15 falls in 鶺鴒鳴 (perennial 09-13 – 09-17).
    func testKoResolvedForAutumnDate() throws {
        let manifest = try loadBundledManifest()
        let date = makeUTCDate(month: 9, day: 15)

        let resolved = try XCTUnwrap(
            TodayResolver.resolve(date: date, manifest: manifest),
            "Resolver must return a non-nil ResolvedDay for 2026-09-15"
        )

        XCTAssertEqual(resolved.ko.kanji, "鶺鴒鳴", "09-15 must resolve to Ko kanji 鶺鴒鳴")
        XCTAssertEqual(resolved.ko.reading.ja, "せきれいなく", "09-15 must resolve to Ko reading.ja せきれいなく")
    }

    // MARK: - AC3 (slice #31): Kō boundary day resolves to exactly one Kō (inclusive)

    /// Boundary test: 2026-06-06 is the START of 螳螂生 (perennial 06-06 – 06-10).
    func testKoBoundaryStartDayResolvesToExactlyOneKo() throws {
        let manifest = try loadBundledManifest()
        let date = makeUTCDate(month: 6, day: 6)

        let resolved = try XCTUnwrap(
            TodayResolver.resolve(date: date, manifest: manifest),
            "Resolver must return a non-nil ResolvedDay for 2026-06-06 (Ko boundary start)"
        )

        XCTAssertEqual(resolved.ko.kanji, "螳螂生", "06-06 (start of range) must resolve to Ko kanji 螳螂生")
        XCTAssertEqual(resolved.ko.reading.ja, "かまきりしょうず", "06-06 (start of range) must resolve to Ko reading.ja かまきりしょうず")
    }

    // MARK: - slice #32: ResolvedDay carries the parent Sekki (full triple)

    /// Winter (2026-01-07): Ko 芹乃栄 belongs to Sekki 小寒 (id: shoukan).
    func testSekkiResolvedForWinterDate() throws {
        let manifest = try loadBundledManifest()
        let date = makeUTCDate(month: 1, day: 7)

        let resolved = try XCTUnwrap(
            TodayResolver.resolve(date: date, manifest: manifest),
            "Resolver must return a non-nil ResolvedDay for 2026-01-07"
        )

        XCTAssertEqual(resolved.ko.kanji, "芹乃栄", "01-07 must resolve to Ko kanji 芹乃栄")
        XCTAssertEqual(resolved.sekki.id, "shoukan", "01-07 Ko belongs to Sekki id shoukan")
        XCTAssertEqual(resolved.sekki.kanji, "小寒", "01-07 Sekki kanji must be 小寒")
        XCTAssertEqual(resolved.sekki.reading.ja, "しょうかん", "01-07 Sekki reading.ja must be しょうかん")
    }

    /// Spring (2026-04-07): Ko 玄鳥至 belongs to Sekki 清明 (id: seimei).
    func testSekkiResolvedForSpringDate() throws {
        let manifest = try loadBundledManifest()
        let date = makeUTCDate(month: 4, day: 7)

        let resolved = try XCTUnwrap(
            TodayResolver.resolve(date: date, manifest: manifest),
            "Resolver must return a non-nil ResolvedDay for 2026-04-07"
        )

        XCTAssertEqual(resolved.ko.kanji, "玄鳥至", "04-07 must resolve to Ko kanji 玄鳥至")
        XCTAssertEqual(resolved.sekki.id, "seimei", "04-07 Ko belongs to Sekki id seimei")
        XCTAssertEqual(resolved.sekki.kanji, "清明", "04-07 Sekki kanji must be 清明")
        XCTAssertEqual(resolved.sekki.reading.ja, "せいめい", "04-07 Sekki reading.ja must be せいめい")
    }

    /// Summer (2026-07-09): Ko 温風至 belongs to Sekki 小暑 (id: shousho).
    func testSekkiResolvedForSummerDate() throws {
        let manifest = try loadBundledManifest()
        let date = makeUTCDate(month: 7, day: 9)

        let resolved = try XCTUnwrap(
            TodayResolver.resolve(date: date, manifest: manifest),
            "Resolver must return a non-nil ResolvedDay for 2026-07-09"
        )

        XCTAssertEqual(resolved.ko.kanji, "温風至", "07-09 must resolve to Ko kanji 温風至")
        XCTAssertEqual(resolved.sekki.id, "shousho", "07-09 Ko belongs to Sekki id shousho")
        XCTAssertEqual(resolved.sekki.kanji, "小暑", "07-09 Sekki kanji must be 小暑")
        XCTAssertEqual(resolved.sekki.reading.ja, "しょうしょ", "07-09 Sekki reading.ja must be しょうしょ")
    }

    /// Autumn (2026-09-15): Ko 鶺鴒鳴 belongs to Sekki 白露 (id: hakuro).
    func testSekkiResolvedForAutumnDate() throws {
        let manifest = try loadBundledManifest()
        let date = makeUTCDate(month: 9, day: 15)

        let resolved = try XCTUnwrap(
            TodayResolver.resolve(date: date, manifest: manifest),
            "Resolver must return a non-nil ResolvedDay for 2026-09-15"
        )

        XCTAssertEqual(resolved.ko.kanji, "鶺鴒鳴", "09-15 must resolve to Ko kanji 鶺鴒鳴")
        XCTAssertEqual(resolved.sekki.id, "hakuro", "09-15 Ko belongs to Sekki id hakuro")
        XCTAssertEqual(resolved.sekki.kanji, "白露", "09-15 Sekki kanji must be 白露")
        XCTAssertEqual(resolved.sekki.reading.ja, "はくろ", "09-15 Sekki reading.ja must be はくろ")
    }

    /// Boundary (2026-06-06): Ko 螳螂生 (start of 芒種, id: boshu).
    func testSekkiResolvedForKoBoundaryDate() throws {
        let manifest = try loadBundledManifest()
        let date = makeUTCDate(month: 6, day: 6)

        let resolved = try XCTUnwrap(
            TodayResolver.resolve(date: date, manifest: manifest),
            "Resolver must return a non-nil ResolvedDay for 2026-06-06"
        )

        XCTAssertEqual(resolved.ko.kanji, "螳螂生", "06-06 must resolve to Ko kanji 螳螂生")
        XCTAssertEqual(resolved.sekki.id, "boshu", "06-06 Ko belongs to Sekki id boshu")
        XCTAssertEqual(resolved.sekki.kanji, "芒種", "06-06 Sekki kanji must be 芒種")
        XCTAssertEqual(resolved.sekki.reading.ja, "ぼうしゅ", "06-06 Sekki reading.ja must be ぼうしゅ")
    }
}
