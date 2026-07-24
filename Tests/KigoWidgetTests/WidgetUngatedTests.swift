@testable import KigoCore
import XCTest
import SwiftUI

// MARK: - WidgetUngatedTests
//
// Slice C7: Proves the widget backdrop reveal is unconditional — no entitlement gate.
//
// `WidgetTimelineBuilder` accepts no `entitlementStore` parameter and always
// produces entries carrying a non-empty `backdropAssetName` (Task 4 image pivot:
// keyed on the resolved day's Sekki id, superseding the retired `showsImage`
// flag). These tests verify that contract directly, plus the rollover-ordering
// tests migrated from WidgetTimelineTests.
//
// Screenshot evidence: a host-rendered PNG of KigoWidgetView is attached as
// `slice-C7-widget-ungated.png` with `.keepAlways` lifetime so it survives the
// test run and is discoverable in the Xcode results bundle.
final class WidgetUngatedTests: XCTestCase {

    // MARK: - Helpers

    /// UTC calendar used for deterministic day-key derivation.
    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    /// Creates a UTC `Date` for the given month and day (year defaults to 2026).
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

    /// Builds a minimal one-day manifest sufficient for TodayResolver to resolve.
    private func makeMinimalManifest(dayKey: String,
                                     year: Int = 2026,
                                     kanji: String = "蛍",
                                     reading: String = "ほたる",
                                     imageId: String = "img-001") -> Manifest {
        let entry = DailyMapEntry(
            kanji: kanji,
            reading: LocalizedText(ja: reading),
            description: LocalizedText(ja: "Fireflies glow in summer dusk.")
        )
        let ko = Ko(
            kanji: "腐草為螢",
            reading: LocalizedText(ja: "くされたるくさほたるとなる"),
            gloss: "rotten grass becomes fireflies",
            sekkiId: "shousho",
            dateRange: DateRange(start: dayKey, end: dayKey),
            description: LocalizedText(ja: "腐った草からホタルが生まれると古人は信じた。")
        )
        let sekki = Sekki(
            id: "shousho",
            kanji: "小暑",
            reading: LocalizedText(ja: "しょうしょ"),
            gloss: LocalizedText(ja: "暑さが増してくる"),
            description: LocalizedText(ja: "本格的な暑さが始まる時期。")
        )
        return Manifest(
            schemaVersion: "1.0",
            version: 1,
            dailyMap: ["\(year)-\(dayKey)": entry],
            ko: [ko],
            sekki: [sekki]
        )
    }

    // MARK: - AC: backdrop is unconditionally present (no entitlement parameter)

    /// AC: systemSmall context — entry built by WidgetTimelineBuilder(dateProvider:manifest:)
    /// with no entitlementStore argument carries a non-empty backdropAssetName keyed on
    /// the resolved Sekki id.
    func testBackdropAlwaysPresent_systemSmall() {
        let dayKey = "06-14"
        let manifest = makeMinimalManifest(dayKey: dayKey, imageId: "img-firefly")
        let date = makeUTCDate(month: 6, day: 14)
        let provider = FixedDateProvider(date: date)

        let builder = WidgetTimelineBuilder(dateProvider: provider, manifest: manifest)
        let entry = builder.buildEntry()

        XCTAssertNotNil(entry, "Builder must return a non-nil entry for a known date")
        XCTAssertEqual(entry!.backdropAssetName, "backdrop-shousho",
                       "backdropAssetName must be unconditionally present, keyed on the Sekki id — no entitlement gate (systemSmall)")
    }

    /// AC: systemMedium context — entry built by WidgetTimelineBuilder(dateProvider:manifest:)
    /// with no entitlementStore argument carries a non-empty backdropAssetName for a
    /// different injected date.
    func testBackdropAlwaysPresent_systemMedium() {
        let dayKey = "07-07"
        let manifest = makeMinimalManifest(dayKey: dayKey,
                                           kanji: "天の川",
                                           reading: "あまのがわ",
                                           imageId: "img-milky")
        let date = makeUTCDate(month: 7, day: 7)
        let provider = FixedDateProvider(date: date)

        let builder = WidgetTimelineBuilder(dateProvider: provider, manifest: manifest)
        let entry = builder.buildEntry()

        XCTAssertNotNil(entry, "Builder must return a non-nil entry for 07-07")
        XCTAssertEqual(entry!.backdropAssetName, "backdrop-shousho",
                       "backdropAssetName must be unconditionally present, keyed on the Sekki id — no entitlement gate (systemMedium)")
    }

    // MARK: - Rollover ordering (migrated from WidgetTimelineTests)

    /// Two-entry structure: buildTimeline returns exactly 2 entries, first at the
    /// injected date, second at the next UTC midnight.
    func testTimelineHasTwoEntriesWithCorrectDates() {
        let todayKey = "06-14"
        let tomorrowKey = "06-15"
        let todayEntry = DailyMapEntry(kanji: "蛍", reading: LocalizedText(ja: "ほたる"),
                                       description: LocalizedText(ja: "Today."))
        let tomorrowEntry = DailyMapEntry(kanji: "朝露", reading: LocalizedText(ja: "あさつゆ"),
                                          description: LocalizedText(ja: "Tomorrow."))
        let ko = Ko(kanji: "腐草為螢",
                    reading: LocalizedText(ja: "くされたるくさほたるとなる"),
                    gloss: "rotten grass becomes fireflies",
                    sekkiId: "shousho",
                    dateRange: DateRange(start: todayKey, end: todayKey),
                    description: LocalizedText(ja: "腐った草からホタルが生まれると古人は信じた。"))
        let nextKo = Ko(kanji: "土潤溽暑",
                        reading: LocalizedText(ja: "つちうるおうてむしあつし"),
                        gloss: "earth is damp and sultry",
                        sekkiId: "shousho",
                        dateRange: DateRange(start: tomorrowKey, end: tomorrowKey),
                        description: LocalizedText(ja: "大地が湿り気を帯び、蒸し暑さが極まる。"))
        let sekki = Sekki(id: "shousho", kanji: "小暑",
                          reading: LocalizedText(ja: "しょうしょ"),
                          gloss: LocalizedText(ja: "暑さが増してくる"),
                          description: LocalizedText(ja: "本格的な暑さが始まる時期。"))
        let manifest = Manifest(schemaVersion: "1.0", version: 1,
                                dailyMap: ["2026-\(todayKey)": todayEntry, "2026-\(tomorrowKey)": tomorrowEntry],
                                ko: [ko, nextKo], sekki: [sekki])

        let today = makeUTCDate(month: 6, day: 14, hour: 12)
        let builder = WidgetTimelineBuilder(dateProvider: FixedDateProvider(date: today), manifest: manifest)
        let timeline = builder.buildTimeline(calendar: utcCalendar)

        XCTAssertEqual(timeline.count, 2, "Timeline must have exactly 2 entries")
        XCTAssertEqual(timeline[0].date, today, "First entry date must equal the injected date")

        let expectedMidnight = makeUTCDate(month: 6, day: 15, hour: 0)
        XCTAssertEqual(timeline[1].date, expectedMidnight,
                       "Second entry date must be the next UTC midnight")
    }

    /// Year-boundary rollover: Dec 31 2026 → Jan 1 2027 midnight.
    func testYearBoundaryRollover() {
        let dec31Entry = DailyMapEntry(kanji: "年の瀬", reading: LocalizedText(ja: "としのせ"),
                                       description: LocalizedText(ja: "Year end."))
        let jan01Entry = DailyMapEntry(kanji: "初日の出", reading: LocalizedText(ja: "はつひので"),
                                       description: LocalizedText(ja: "New year sunrise."))
        let koDec = Ko(kanji: "雪", reading: LocalizedText(ja: "ゆき"),
                       gloss: "snow", sekkiId: "touji",
                       dateRange: DateRange(start: "12-31", end: "12-31"),
                       description: LocalizedText(ja: "冬の雪。"))
        let koJan = Ko(kanji: "初日の出", reading: LocalizedText(ja: "はつひので"),
                       gloss: "first sunrise", sekkiId: "touji",
                       dateRange: DateRange(start: "01-01", end: "01-01"),
                       description: LocalizedText(ja: "元日の日の出。"))
        let sekki = Sekki(id: "touji", kanji: "冬至",
                          reading: LocalizedText(ja: "とうじ"),
                          gloss: LocalizedText(ja: "冬至"),
                          description: LocalizedText(ja: "冬の折り返し点。"))
        let manifest = Manifest(schemaVersion: "1.0", version: 1,
                                dailyMap: ["2026-12-31": dec31Entry, "2027-01-01": jan01Entry],
                                ko: [koDec, koJan], sekki: [sekki])

        let today = makeUTCDate(year: 2026, month: 12, day: 31, hour: 12)
        let builder = WidgetTimelineBuilder(dateProvider: FixedDateProvider(date: today), manifest: manifest)
        let timeline = builder.buildTimeline(calendar: utcCalendar)

        XCTAssertEqual(timeline.count, 2, "Timeline must have exactly 2 entries at year boundary")

        var comps = DateComponents()
        comps.year = 2027
        comps.month = 1
        comps.day = 1
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        let jan1 = utcCalendar.date(from: comps)!
        XCTAssertEqual(timeline[1].date, jan1,
                       "Second entry date must be 2027-01-01 00:00:00 UTC")
        XCTAssertEqual(timeline[1].kanji, "初日の出",
                       "Second entry kanji must match Jan 1 manifest entry")
    }

    // MARK: - Screenshot evidence

    /// Host-renders KigoWidgetView with the backdrop always present and attaches it as
    /// `slice-C7-widget-ungated.png` with `.keepAlways` lifetime.
    ///
    /// This is the required screenshot evidence for slice C7.
    /// Test identifier: KigoWidgetTests/WidgetUngatedTests/testScreenshot
    func testScreenshot() async throws {
        // Build a resolved entry with a non-empty backdrop via the real builder (no arg needed).
        let dayKey = "06-14"
        let manifest = makeMinimalManifest(dayKey: dayKey,
                                           kanji: "蛍",
                                           reading: "ほたる",
                                           imageId: "img-firefly")
        let date = makeUTCDate(month: 6, day: 14)
        let provider = FixedDateProvider(date: date)
        let builder = WidgetTimelineBuilder(dateProvider: provider, manifest: manifest)
        guard let entry = builder.buildEntry() else {
            XCTFail("Builder returned nil — cannot render screenshot")
            return
        }

        XCTAssertFalse(entry.backdropAssetName.isEmpty, "backdropAssetName must be non-empty before rendering")

        // Host-render on MainActor (ImageRenderer and SwiftUI view are @MainActor-bound).
        let pngData: Data? = await MainActor.run {
            let view = KigoWidgetView(entry: entry)
                .frame(width: 169, height: 169)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2.0
            return renderer.uiImage?.pngData()
        }

        guard let pngData else {
            XCTFail("ImageRenderer failed to produce PNG data")
            return
        }

        XCTAssertGreaterThan(pngData.count, 0, "PNG data must be non-empty")

        let attachment = XCTAttachment(data: pngData, uniformTypeIdentifier: "public.png")
        attachment.name = "slice-C7-widget-ungated.png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
