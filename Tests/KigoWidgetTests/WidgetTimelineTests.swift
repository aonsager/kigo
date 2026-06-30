import XCTest

// MARK: - WidgetTimelineTests
//
// Slice #69: Walking skeleton — proves the widget test target, scheme wiring,
// and shared-code reach all connect end-to-end.
//
// Slice #70: Timeline rollover — `buildTimeline(calendar:)` returns a two-entry
// ordered timeline: first entry for the current date, second entry dated at the
// following local midnight and resolving to the next day's Kigo.
//
// Tests a pure `WidgetTimelineBuilder` that, given:
//   - an injected `DateProvider` (fixed date for determinism)
//   - a loaded `Manifest`
//   - a widget family
// produces a `KigoWidgetEntry` whose kanji/reading/imageId match the
// manifest's daily-map entry for that date's day-key.
//
// Resolution is delegated to `TodayResolver` — no re-implementation of
// the day-key or Ko/Sekki lookup logic here.
final class WidgetTimelineTests: XCTestCase {

    // MARK: - Helpers

    /// UTC calendar used throughout these tests to guarantee deterministic day-key derivation.
    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    /// Creates a UTC `Date` for the given month and day. The year defaults to 2026
    /// because the daily map is keyed by absolute `2026-MM-DD` after the ADR 0016 migration;
    /// the year-boundary rollover test overrides it.
    private func makeUTCDate(year: Int = 2026, month: Int, day: Int, hour: Int = 12) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = 0
        comps.second = 0
        return utcCalendar.date(from: comps)!
    }

    /// Builds a minimal two-day manifest with entries for `dayKey` and `nextDayKey`.
    /// Each day gets its own Ko (sharing one Sekki) for the resolver to work.
    /// `dayKey`/`nextDayKey` are perennial `MM-DD` (used for the Kō range and to derive the
    /// absolute daily-map key). `year`/`nextYear` form the absolute `YYYY-MM-DD` daily-map keys
    /// (default 2026; the year-boundary test passes 2026/2027).
    private func makeTwoDayManifest(dayKey: String,
                                    kanji: String,
                                    reading: String,
                                    imageId: String,
                                    nextDayKey: String,
                                    nextKanji: String,
                                    nextReading: String,
                                    nextImageId: String,
                                    year: Int = 2026,
                                    nextYear: Int = 2026) -> Manifest {
        let placeholderAttribution = Attribution(
            title: LocalizedText(ja: "季語の風景"),
            credit: LocalizedText(ja: "撮影者不明"),
            license: LocalizedText(ja: "パブリックドメイン")
        )
        let entry = DailyMapEntry(kanji: kanji, reading: LocalizedText(ja: reading),
                                  description: LocalizedText(ja: "Today's Kigo."), imageId: imageId,
                                  attribution: placeholderAttribution)
        let nextEntry = DailyMapEntry(kanji: nextKanji, reading: LocalizedText(ja: nextReading),
                                     description: LocalizedText(ja: "Tomorrow's Kigo."), imageId: nextImageId,
                                     attribution: placeholderAttribution)
        let ko = Ko(kanji: "腐草為螢",
                    reading: LocalizedText(ja: "くされたるくさほたるとなる"),
                    gloss: "rotten grass becomes fireflies",
                    sekkiId: "shousho",
                    dateRange: DateRange(start: dayKey, end: dayKey),
                    description: LocalizedText(ja: "腐った草からホタルが生まれると古人は信じた。"))
        let nextKo = Ko(kanji: "土潤溽暑",
                        reading: LocalizedText(ja: "つちうるおうてむしあつし"),
                        gloss: "earth is damp and sultry",
                        sekkiId: "shousho",
                        dateRange: DateRange(start: nextDayKey, end: nextDayKey),
                        description: LocalizedText(ja: "大地が湿り気を帯び、蒸し暑さが極まる。"))
        let sekki = Sekki(id: "shousho", kanji: "小暑", reading: LocalizedText(ja: "しょうしょ"),
                          gloss: LocalizedText(ja: "暑さが増してくる"),
                          description: LocalizedText(ja: "本格的な暑さが始まる時期。"))
        return Manifest(schemaVersion: "1.0",
                        version: 1,
                        dailyMap: ["\(year)-\(dayKey)": entry, "\(nextYear)-\(nextDayKey)": nextEntry],
                        ko: [ko, nextKo],
                        sekki: [sekki])
    }

    /// Builds a minimal manifest with one daily-map entry, one Ko, one Sekki —
    /// enough for the builder to resolve successfully without touching the bundle.
    /// `dayKey` is perennial `MM-DD` (used for the Kō range and to derive the absolute
    /// daily-map key); `year` (default 2026) forms the absolute `YYYY-MM-DD` daily-map key.
    private func makeMinimalManifest(dayKey: String,
                                     year: Int = 2026,
                                     kanji: String = "蛍",
                                     reading: String = "ほたる",
                                     imageId: String = "img-001") -> Manifest {
        let entry = DailyMapEntry(kanji: kanji,
                                  reading: LocalizedText(ja: reading),
                                  description: LocalizedText(ja: "Fireflies glow in summer dusk."),
                                  imageId: imageId,
                                  attribution: Attribution(
                                      title: LocalizedText(ja: "季語の風景"),
                                      credit: LocalizedText(ja: "撮影者不明"),
                                      license: LocalizedText(ja: "パブリックドメイン")
                                  ))
        let ko = Ko(kanji: "腐草為螢",
                    reading: LocalizedText(ja: "くされたるくさほたるとなる"),
                    gloss: "rotten grass becomes fireflies",
                    sekkiId: "shousho",
                    dateRange: DateRange(start: dayKey, end: dayKey),
                    description: LocalizedText(ja: "腐った草からホタルが生まれると古人は信じた。"))
        let sekki = Sekki(id: "shousho", kanji: "小暑", reading: LocalizedText(ja: "しょうしょ"),
                          gloss: LocalizedText(ja: "暑さが増してくる"),
                          description: LocalizedText(ja: "本格的な暑さが始まる時期。"))
        return Manifest(schemaVersion: "1.0",
                        version: 1,
                        dailyMap: ["\(year)-\(dayKey)": entry],
                        ko: [ko],
                        sekki: [sekki])
    }

    // MARK: - AC1 + AC2: entry fields match manifest daily-map for the injected date

    /// Injecting a fixed date and a minimal manifest: the built entry's kanji,
    /// reading, and imageId must equal the manifest's daily-map entry for that date.
    func testBuilderEntryMatchesManifestForFixedDate() {
        let dayKey = "06-14"
        let manifest = makeMinimalManifest(dayKey: dayKey,
                                           kanji: "蛍",
                                           reading: "ほたる",
                                           imageId: "img-firefly")
        let date = makeUTCDate(month: 6, day: 14)
        let provider = FixedDateProvider(date: date)

        let builder = WidgetTimelineBuilder(dateProvider: provider, manifest: manifest)
        let entry = builder.buildEntry()

        XCTAssertNotNil(entry, "Builder must return a non-nil entry for a known date")
        XCTAssertEqual(entry?.kanji, "蛍",     "Entry kanji must match manifest daily-map")
        XCTAssertEqual(entry?.reading, "ほたる", "Entry reading must match manifest daily-map")
        XCTAssertEqual(entry?.imageId, "img-firefly", "Entry imageId must match manifest daily-map")
        XCTAssertEqual(entry?.date, date,       "Entry date must equal the injected date")
    }

    /// Verify that different injected dates each produce the correct manifest entry.
    func testBuilderEntryMatchesManifestForMultipleDates() {
        let cases: [(month: Int, day: Int, kanji: String, reading: String, imageId: String)] = [
            (1,  1,  "寒椿",   "かんつばき",   "img-001"),
            (7,  7,  "天の川", "あまのがわ",   "img-002"),
            (12, 31, "年の瀬", "としのせ",     "img-003"),
        ]

        for c in cases {
            let dayKey = String(format: "%02d-%02d", c.month, c.day)
            let manifest = makeMinimalManifest(dayKey: dayKey,
                                               kanji: c.kanji,
                                               reading: c.reading,
                                               imageId: c.imageId)
            let date = makeUTCDate(month: c.month, day: c.day)
            let provider = FixedDateProvider(date: date)

            let builder = WidgetTimelineBuilder(dateProvider: provider, manifest: manifest)
            let entry = builder.buildEntry()

            XCTAssertNotNil(entry, "Builder must return non-nil for \(dayKey)")
            XCTAssertEqual(entry?.kanji, c.kanji,   "kanji mismatch for \(dayKey)")
            XCTAssertEqual(entry?.reading, c.reading, "reading mismatch for \(dayKey)")
            XCTAssertEqual(entry?.imageId, c.imageId, "imageId mismatch for \(dayKey)")
        }
    }

    /// Builder returns nil when the manifest has no entry for the resolved date.
    func testBuilderReturnsNilForUnknownDate() {
        let manifest = makeMinimalManifest(dayKey: "01-01")
        let date = makeUTCDate(month: 6, day: 14) // not in manifest
        let provider = FixedDateProvider(date: date)

        let builder = WidgetTimelineBuilder(dateProvider: provider, manifest: manifest)
        let entry = builder.buildEntry()

        XCTAssertNil(entry, "Builder must return nil when manifest has no entry for the resolved date")
    }

    // MARK: - Slice #70: Timeline rollover tests

    /// AC1: `buildTimeline` returns exactly 2 entries in order; the second entry's
    /// date is the next UTC midnight after the injected date.
    ///
    /// Using a UTC calendar for both construction and the `buildTimeline(calendar:)` call
    /// guarantees the "next midnight" assertion is deterministic regardless of the
    /// test-runner's local timezone (see ADR 0010).
    func testTimelineHasTwoEntriesAndSecondIsAtNextMidnight() {
        let todayDayKey = "06-14"
        let tomorrowDayKey = "06-15"
        let manifest = makeTwoDayManifest(
            dayKey: todayDayKey, kanji: "蛍", reading: "ほたる", imageId: "img-today",
            nextDayKey: tomorrowDayKey, nextKanji: "朝露", nextReading: "あさつゆ", nextImageId: "img-tomorrow"
        )
        // Injected date: 2024-06-14 12:00 UTC (midday, well before midnight)
        let today = makeUTCDate(month: 6, day: 14, hour: 12)
        let provider = FixedDateProvider(date: today)
        let builder = WidgetTimelineBuilder(dateProvider: provider, manifest: manifest)

        let timeline = builder.buildTimeline(calendar: utcCalendar)

        XCTAssertEqual(timeline.count, 2, "Timeline must have exactly 2 entries")

        // First entry date == injected date
        XCTAssertEqual(timeline[0].date, today, "First entry date must equal the injected date")

        // Second entry date == next local (UTC) midnight: 2024-06-15 00:00:00 UTC
        let expectedMidnight = makeUTCDate(month: 6, day: 15, hour: 0)
        XCTAssertEqual(timeline[1].date, expectedMidnight,
                       "Second entry date must be the next UTC midnight (2024-06-15 00:00:00 UTC)")
    }

    /// AC2: The second timeline entry resolves to the next day's Kigo (kanji/reading/imageId
    /// matching the manifest entry for the next-day key).
    func testTimelineSecondEntryResolvesToNextDayKigo() {
        let todayDayKey = "06-14"
        let tomorrowDayKey = "06-15"
        let manifest = makeTwoDayManifest(
            dayKey: todayDayKey, kanji: "蛍", reading: "ほたる", imageId: "img-today",
            nextDayKey: tomorrowDayKey, nextKanji: "朝露", nextReading: "あさつゆ", nextImageId: "img-tomorrow"
        )
        let today = makeUTCDate(month: 6, day: 14, hour: 12)
        let provider = FixedDateProvider(date: today)
        let builder = WidgetTimelineBuilder(dateProvider: provider, manifest: manifest)

        let timeline = builder.buildTimeline(calendar: utcCalendar)

        XCTAssertEqual(timeline.count, 2, "Timeline must have exactly 2 entries")

        // First entry = today's Kigo
        XCTAssertEqual(timeline[0].kanji, "蛍", "First entry kanji must match today's manifest entry")
        XCTAssertEqual(timeline[0].reading, "ほたる", "First entry reading must match today's manifest entry")
        XCTAssertEqual(timeline[0].imageId, "img-today", "First entry imageId must match today's manifest entry")

        // Second entry = tomorrow's Kigo
        XCTAssertEqual(timeline[1].kanji, "朝露", "Second entry kanji must match next day's manifest entry")
        XCTAssertEqual(timeline[1].reading, "あさつゆ", "Second entry reading must match next day's manifest entry")
        XCTAssertEqual(timeline[1].imageId, "img-tomorrow", "Second entry imageId must match next day's manifest entry")
    }

    /// AC3: Timeline determinism — injecting `FixedDateProvider` and an explicit calendar
    /// means no real clock dependency. Verify with a different date (year-boundary: Dec 31 → Jan 1).
    func testTimelineRolloverAtYearBoundaryIsDeterministic() {
        let todayDayKey = "12-31"
        let tomorrowDayKey = "01-01"
        // Dec 31 2026 rolls over to Jan 1 2027: the next-day entry lives under the 2027 key.
        let manifest = makeTwoDayManifest(
            dayKey: todayDayKey, kanji: "年の瀬", reading: "としのせ", imageId: "img-dec31",
            nextDayKey: tomorrowDayKey, nextKanji: "初日の出", nextReading: "はつひので", nextImageId: "img-jan01",
            year: 2026, nextYear: 2027
        )
        // 2026-12-31 12:00 UTC
        let today = makeUTCDate(month: 12, day: 31, hour: 12)
        let provider = FixedDateProvider(date: today)
        let builder = WidgetTimelineBuilder(dateProvider: provider, manifest: manifest)

        let timeline = builder.buildTimeline(calendar: utcCalendar)

        XCTAssertEqual(timeline.count, 2, "Timeline must have exactly 2 entries at year boundary")

        // Second entry date = 2027-01-01 00:00:00 UTC
        var comps = DateComponents()
        comps.year = 2027
        comps.month = 1
        comps.day = 1
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        let expectedJan1 = utcCalendar.date(from: comps)!
        XCTAssertEqual(timeline[1].date, expectedJan1,
                       "Second entry date must be 2027-01-01 00:00:00 UTC")

        // Second entry content = Jan 1 Kigo
        XCTAssertEqual(timeline[1].kanji, "初日の出",
                       "Second entry kanji must match Jan 1 manifest entry")
        XCTAssertEqual(timeline[1].imageId, "img-jan01",
                       "Second entry imageId must match Jan 1 manifest entry")
    }

    /// Timeline entries are ordered: first entry's date comes before second entry's date.
    func testTimelineEntriesAreOrdered() {
        let manifest = makeTwoDayManifest(
            dayKey: "07-07", kanji: "天の川", reading: "あまのがわ", imageId: "img-a",
            nextDayKey: "07-08", nextKanji: "朝霧", nextReading: "あさぎり", nextImageId: "img-b"
        )
        let today = makeUTCDate(month: 7, day: 7, hour: 6)
        let provider = FixedDateProvider(date: today)
        let builder = WidgetTimelineBuilder(dateProvider: provider, manifest: manifest)

        let timeline = builder.buildTimeline(calendar: utcCalendar)

        XCTAssertEqual(timeline.count, 2)
        XCTAssertLessThan(timeline[0].date, timeline[1].date,
                          "First entry date must precede second entry date")
    }
}
