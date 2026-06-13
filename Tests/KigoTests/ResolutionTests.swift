import XCTest
@testable import Kigo

// MARK: - ResolutionTests

/// Tests for `TodayResolution` resolver (slice #30).
///
/// The resolver takes an injected `DateProvider` and a loaded `Manifest`, derives
/// the `MM-DD` day-key using the shared UTC calendar, and returns a `ResolvedDay`
/// carrying the matching `DailyMapEntry`.
///
/// All tests use `XCTest` and `@testable import Kigo` — no SwiftUI import.
final class ResolutionTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a UTC `Date` for the given month and day (year is irrelevant for MM-DD lookup).
    private func makeUTCDate(month: Int, day: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var comps = DateComponents()
        comps.year = 2024
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

    // MARK: - AC1 & AC2: Resolver returns the correct DailyMapEntry for a fixed date

    /// AC1 + AC2: Injecting a fixed date (June 13) into the resolver returns the same
    /// `DailyMapEntry` that a direct `dailyMap["06-13"]` lookup yields on the bundled manifest.
    func testResolverReturnsBundledManifestEntryForFixedDate() throws {
        let manifest = try loadBundledManifest()
        let dateProvider = FixedDateProvider(date: makeUTCDate(month: 6, day: 13))

        let resolved = TodayResolver.resolve(date: dateProvider.today, manifest: manifest)

        let expectedEntry = try XCTUnwrap(
            manifest.dailyMap["06-13"],
            "Bundled manifest must have a '06-13' entry"
        )
        XCTAssertNotNil(resolved, "Resolver must return a non-nil ResolvedDay for a known date")
        XCTAssertEqual(
            resolved?.kigoEntry,
            expectedEntry,
            "Resolver must return the same DailyMapEntry as a direct dailyMap['06-13'] lookup"
        )
    }

    /// Verifies that multiple different injected dates each resolve to the correct DailyMapEntry.
    func testResolverReturnsCorrectEntryAcrossMultipleDates() throws {
        let manifest = try loadBundledManifest()

        let testCases: [(month: Int, day: Int)] = [
            (1, 1),    // "01-01" — New Year
            (2, 29),   // "02-29" — leap day
            (6, 13),   // "06-13" — today (as of test authoring)
            (12, 31),  // "12-31" — last day of year
        ]

        for (month, day) in testCases {
            let date = makeUTCDate(month: month, day: day)
            let key = String(format: "%02d-%02d", month, day)
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
        }
    }

    // MARK: - AC3: Shared day-key derivation (compile-time)

    /// AC3: Verifies that DayKey.make(_:) is accessible and produces the expected "MM-DD" string.
    /// This confirms the shared derivation is a public/internal API, not a private detail.
    func testDayKeyMakeProducesCorrectFormat() {
        let june13 = makeUTCDate(month: 6, day: 13)
        let key = DayKey.make(from: june13)
        XCTAssertEqual(key, "06-13", "DayKey.make should format date as MM-DD in UTC")
    }

    func testDayKeyMakeLeapDay() {
        // Feb 29 in 2024 (a leap year)
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
    /// The resolver takes a `Date` and `Manifest` and produces `ResolvedDay?` with no side effects.
    func testResolverIsStateless() throws {
        let manifest = try loadBundledManifest()
        let date = makeUTCDate(month: 6, day: 13)

        // Calling twice with the same inputs must yield equal results.
        let result1 = TodayResolver.resolve(date: date, manifest: manifest)
        let result2 = TodayResolver.resolve(date: date, manifest: manifest)

        XCTAssertEqual(result1?.kigoEntry, result2?.kigoEntry,
            "Resolver must be deterministic — same inputs must yield equal outputs")
    }

    // MARK: - Edge: unknown key

    /// If the manifest has no entry for the derived key (impossible for bundled data,
    /// but possible with a minimal test manifest), the resolver returns nil.
    func testResolverReturnsNilForUnknownKey() {
        let emptyManifest = Manifest(
            schemaVersion: "1.0",
            dailyMap: [:],
            ko: [],
            sekki: []
        )
        let date = makeUTCDate(month: 6, day: 13)
        let resolved = TodayResolver.resolve(date: date, manifest: emptyManifest)
        XCTAssertNil(resolved, "Resolver must return nil when manifest has no entry for the derived key")
    }

    // MARK: - AC1 & AC2 (slice #31): ResolvedDay carries the current Kō per season

    /// Winter (January): 01-07 falls in 芹乃栄 (01-05 – 01-09).
    /// Values pinned from bundled manifest (index 66).
    func testKoResolvedForWinterDate() throws {
        let manifest = try loadBundledManifest()
        let date = makeUTCDate(month: 1, day: 7)

        let resolved = try XCTUnwrap(
            TodayResolver.resolve(date: date, manifest: manifest),
            "Resolver must return a non-nil ResolvedDay for 01-07"
        )

        XCTAssertEqual(resolved.ko.kanji, "芹乃栄", "01-07 must resolve to Ko kanji 芹乃栄")
        XCTAssertEqual(resolved.ko.reading, "せりすなわちさかう", "01-07 must resolve to Ko reading せりすなわちさかう")
    }

    /// Spring (April): 04-07 falls in 玄鳥至 (04-05 – 04-09).
    /// Values pinned from bundled manifest (index 12).
    func testKoResolvedForSpringDate() throws {
        let manifest = try loadBundledManifest()
        let date = makeUTCDate(month: 4, day: 7)

        let resolved = try XCTUnwrap(
            TodayResolver.resolve(date: date, manifest: manifest),
            "Resolver must return a non-nil ResolvedDay for 04-07"
        )

        XCTAssertEqual(resolved.ko.kanji, "玄鳥至", "04-07 must resolve to Ko kanji 玄鳥至")
        XCTAssertEqual(resolved.ko.reading, "つばめきたる", "04-07 must resolve to Ko reading つばめきたる")
    }

    /// Summer (July): 07-09 falls in 温風至 (07-07 – 07-11).
    /// Values pinned from bundled manifest (index 30).
    func testKoResolvedForSummerDate() throws {
        let manifest = try loadBundledManifest()
        let date = makeUTCDate(month: 7, day: 9)

        let resolved = try XCTUnwrap(
            TodayResolver.resolve(date: date, manifest: manifest),
            "Resolver must return a non-nil ResolvedDay for 07-09"
        )

        XCTAssertEqual(resolved.ko.kanji, "温風至", "07-09 must resolve to Ko kanji 温風至")
        XCTAssertEqual(resolved.ko.reading, "あつかぜいたる", "07-09 must resolve to Ko reading あつかぜいたる")
    }

    /// Autumn (September): 09-15 falls in 鶺鴒鳴 (09-13 – 09-17).
    /// Values pinned from bundled manifest (index 43).
    func testKoResolvedForAutumnDate() throws {
        let manifest = try loadBundledManifest()
        let date = makeUTCDate(month: 9, day: 15)

        let resolved = try XCTUnwrap(
            TodayResolver.resolve(date: date, manifest: manifest),
            "Resolver must return a non-nil ResolvedDay for 09-15"
        )

        XCTAssertEqual(resolved.ko.kanji, "鶺鴒鳴", "09-15 must resolve to Ko kanji 鶺鴒鳴")
        XCTAssertEqual(resolved.ko.reading, "せきれいなく", "09-15 must resolve to Ko reading せきれいなく")
    }

    // MARK: - AC3 (slice #31): Kō boundary day resolves to exactly one Kō (inclusive)

    /// Boundary test: 06-06 is the START of 螳螂生 (06-06 – 06-10).
    /// Containment is inclusive (start ≤ key ≤ end), so the boundary day must
    /// resolve to exactly one Kō — 螳螂生 — with no gap or overlap.
    /// Values pinned from bundled manifest (index 24).
    func testKoBoundaryStartDayResolvesToExactlyOneKo() throws {
        let manifest = try loadBundledManifest()
        let date = makeUTCDate(month: 6, day: 6)

        let resolved = try XCTUnwrap(
            TodayResolver.resolve(date: date, manifest: manifest),
            "Resolver must return a non-nil ResolvedDay for 06-06 (Ko boundary start)"
        )

        XCTAssertEqual(resolved.ko.kanji, "螳螂生", "06-06 (start of range) must resolve to Ko kanji 螳螂生")
        XCTAssertEqual(resolved.ko.reading, "かまきりしょうず", "06-06 (start of range) must resolve to Ko reading かまきりしょうず")
    }

    // MARK: - slice #32: ResolvedDay carries the parent Sekki (full triple)

    /// Winter (01-07): Ko 芹乃栄 belongs to Sekki 小寒 (id: shoukan).
    /// Pinned from bundled manifest.
    func testSekkiResolvedForWinterDate() throws {
        let manifest = try loadBundledManifest()
        let date = makeUTCDate(month: 1, day: 7)

        let resolved = try XCTUnwrap(
            TodayResolver.resolve(date: date, manifest: manifest),
            "Resolver must return a non-nil ResolvedDay for 01-07"
        )

        XCTAssertEqual(resolved.ko.kanji, "芹乃栄", "01-07 must resolve to Ko kanji 芹乃栄")
        XCTAssertEqual(resolved.sekki.id, "shoukan", "01-07 Ko belongs to Sekki id shoukan")
        XCTAssertEqual(resolved.sekki.kanji, "小寒", "01-07 Sekki kanji must be 小寒")
        XCTAssertEqual(resolved.sekki.reading, "しょうかん", "01-07 Sekki reading must be しょうかん")
    }

    /// Spring (04-07): Ko 玄鳥至 belongs to Sekki 清明 (id: seimei).
    /// Pinned from bundled manifest.
    func testSekkiResolvedForSpringDate() throws {
        let manifest = try loadBundledManifest()
        let date = makeUTCDate(month: 4, day: 7)

        let resolved = try XCTUnwrap(
            TodayResolver.resolve(date: date, manifest: manifest),
            "Resolver must return a non-nil ResolvedDay for 04-07"
        )

        XCTAssertEqual(resolved.ko.kanji, "玄鳥至", "04-07 must resolve to Ko kanji 玄鳥至")
        XCTAssertEqual(resolved.sekki.id, "seimei", "04-07 Ko belongs to Sekki id seimei")
        XCTAssertEqual(resolved.sekki.kanji, "清明", "04-07 Sekki kanji must be 清明")
        XCTAssertEqual(resolved.sekki.reading, "せいめい", "04-07 Sekki reading must be せいめい")
    }

    /// Summer (07-09): Ko 温風至 belongs to Sekki 小暑 (id: shousho).
    /// Pinned from bundled manifest.
    func testSekkiResolvedForSummerDate() throws {
        let manifest = try loadBundledManifest()
        let date = makeUTCDate(month: 7, day: 9)

        let resolved = try XCTUnwrap(
            TodayResolver.resolve(date: date, manifest: manifest),
            "Resolver must return a non-nil ResolvedDay for 07-09"
        )

        XCTAssertEqual(resolved.ko.kanji, "温風至", "07-09 must resolve to Ko kanji 温風至")
        XCTAssertEqual(resolved.sekki.id, "shousho", "07-09 Ko belongs to Sekki id shousho")
        XCTAssertEqual(resolved.sekki.kanji, "小暑", "07-09 Sekki kanji must be 小暑")
        XCTAssertEqual(resolved.sekki.reading, "しょうしょ", "07-09 Sekki reading must be しょうしょ")
    }

    /// Autumn (09-15): Ko 鶺鴒鳴 belongs to Sekki 白露 (id: hakuro).
    /// Pinned from bundled manifest.
    func testSekkiResolvedForAutumnDate() throws {
        let manifest = try loadBundledManifest()
        let date = makeUTCDate(month: 9, day: 15)

        let resolved = try XCTUnwrap(
            TodayResolver.resolve(date: date, manifest: manifest),
            "Resolver must return a non-nil ResolvedDay for 09-15"
        )

        XCTAssertEqual(resolved.ko.kanji, "鶺鴒鳴", "09-15 must resolve to Ko kanji 鶺鴒鳴")
        XCTAssertEqual(resolved.sekki.id, "hakuro", "09-15 Ko belongs to Sekki id hakuro")
        XCTAssertEqual(resolved.sekki.kanji, "白露", "09-15 Sekki kanji must be 白露")
        XCTAssertEqual(resolved.sekki.reading, "はくろ", "09-15 Sekki reading must be はくろ")
    }

    /// Boundary (06-06): Ko 螳螂生 (start of 芒種, id: boshu).
    /// Pinned from bundled manifest.
    func testSekkiResolvedForKoBoundaryDate() throws {
        let manifest = try loadBundledManifest()
        let date = makeUTCDate(month: 6, day: 6)

        let resolved = try XCTUnwrap(
            TodayResolver.resolve(date: date, manifest: manifest),
            "Resolver must return a non-nil ResolvedDay for 06-06"
        )

        XCTAssertEqual(resolved.ko.kanji, "螳螂生", "06-06 must resolve to Ko kanji 螳螂生")
        XCTAssertEqual(resolved.sekki.id, "boshu", "06-06 Ko belongs to Sekki id boshu")
        XCTAssertEqual(resolved.sekki.kanji, "芒種", "06-06 Sekki kanji must be 芒種")
        XCTAssertEqual(resolved.sekki.reading, "ぼうしゅ", "06-06 Sekki reading must be ぼうしゅ")
    }

    /// Leap day (02-29): absorbed into Ko 霞始靆 (sekkiId: usui → Sekki 雨水).
    /// Per ADR 0005 amendment, 02-29 maps to 霞始靆 in the bundled manifest.
    func testSekkiResolvedForLeapDay() throws {
        let manifest = try loadBundledManifest()
        let date = makeUTCDate(month: 2, day: 29)

        let resolved = try XCTUnwrap(
            TodayResolver.resolve(date: date, manifest: manifest),
            "Resolver must return a non-nil ResolvedDay for 02-29"
        )

        XCTAssertEqual(resolved.ko.kanji, "霞始靆", "02-29 must resolve to Ko kanji 霞始靆 (leap-day absorbing Ko)")
        XCTAssertEqual(resolved.sekki.id, "usui", "02-29 Ko belongs to Sekki id usui")
        XCTAssertEqual(resolved.sekki.kanji, "雨水", "02-29 Sekki kanji must be 雨水")
        XCTAssertEqual(resolved.sekki.reading, "うすい", "02-29 Sekki reading must be うすい")
    }
}
