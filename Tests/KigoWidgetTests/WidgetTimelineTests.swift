import XCTest

// MARK: - WidgetTimelineTests
//
// Slice #69: Walking skeleton — proves the widget test target, scheme wiring,
// and shared-code reach all connect end-to-end.
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

    /// Builds a minimal manifest with one daily-map entry, one Ko, one Sekki —
    /// enough for the builder to resolve successfully without touching the bundle.
    private func makeMinimalManifest(dayKey: String,
                                     kanji: String = "蛍",
                                     reading: String = "ほたる",
                                     imageId: String = "img-001") -> Manifest {
        let entry = DailyMapEntry(kanji: kanji,
                                  reading: reading,
                                  description: "Fireflies glow in summer dusk.",
                                  imageId: imageId)
        let ko = Ko(kanji: "腐草為螢",
                    reading: "くされたるくさほたるとなる",
                    gloss: "rotten grass becomes fireflies",
                    sekkiId: "shousho",
                    dateRange: DateRange(start: dayKey, end: dayKey))
        let sekki = Sekki(id: "shousho", kanji: "小暑", reading: "しょうしょ")
        return Manifest(schemaVersion: "1.0",
                        dailyMap: [dayKey: entry],
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
}
