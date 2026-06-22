import XCTest
@testable import Kigo

// MARK: - AlmanacWiringTests
//
// Slice #122: verifies that ContentStore.screenState emits .today carrying
// AlmanacPositions alongside ResolvedDay, and falls back to .unavailablePlaceholder
// when AlmanacResolver returns nil (date outside all Ko ranges).
//
// Both tests use in-process fakes (no simulator launch, no network, no UI) and the
// bundled manifest so they run fast and deterministically.

final class AlmanacWiringTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a UTC `Date` for the given year/month/day.
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

    // MARK: - AC: screenState emits .today with AlmanacPositions for 2026-06-16

    /// When the manifest loads and AlmanacResolver resolves 2026-06-16 (梅子黄),
    /// screenState must be .today carrying:
    ///   - a ResolvedDay (Kigo + Ko + Sekki)
    ///   - AlmanacPositions with koYearPosition == 27 and koYearTotal == 72
    ///
    /// This verifies the full wiring: ContentStore.screenState calls AlmanacResolver
    /// and packages the result in the .today case payload.
    @MainActor
    func testScreenStateCarriesAlmanacPositionsFor20260616() async throws {
        let manifest = try loadBundledManifest()
        let source = FakeContentSource(manifest: manifest)
        let june16 = FixedDateProvider(date: makeUTCDate(month: 6, day: 16))
        let store = ContentStore(source: source, dateProvider: june16)

        await store.waitForLoad()

        guard case .today(let resolved, let positions) = store.screenState else {
            XCTFail("screenState must be .today for 2026-06-16 (梅子黄) against bundled manifest, got \(store.screenState)")
            return
        }

        XCTAssertEqual(
            resolved.ko.kanji,
            "梅子黄",
            "ResolvedDay.ko.kanji must be 梅子黄 for 06-16"
        )
        XCTAssertEqual(
            positions.koYearPosition,
            27,
            "AlmanacPositions.koYearPosition must be 27 for 2026-06-16 (梅子黄) under risshun-anchored ordering"
        )
        XCTAssertEqual(
            positions.koYearTotal,
            72,
            "AlmanacPositions.koYearTotal must be 72"
        )
    }

    // MARK: - AC: screenState == .unavailablePlaceholder when date is outside all Ko ranges

    /// When the injected manifest has Ko ranges that do not cover the resolved date,
    /// AlmanacResolver returns nil. ContentStore.screenState must fall back to
    /// .unavailablePlaceholder — never a spinner that cannot resolve.
    ///
    /// Uses a minimal manifest with a single Ko covering only 01-01 to 01-05,
    /// then injects date 2026-06-16 (not in any Ko range).
    @MainActor
    func testScreenStateIsUnavailablePlaceholderWhenAlmanacResolverReturnsNil() async throws {
        // Minimal manifest: one daily-map entry and one Ko covering only 01-01–01-05.
        // Date 2026-06-16 has a daily-map entry but no containing Ko — resolver returns nil.
        let dailyMap: [String: DailyMapEntry] = [
            "2026-06-16": DailyMapEntry(
                kanji: "梅子黄",
                reading: LocalizedText(ja: "うめのみきばむ"),
                description: LocalizedText(ja: "Plums turn yellow."),
                imageId: "img-0616",
                attribution: Attribution(
                    title: LocalizedText(ja: "季語の風景"),
                    credit: LocalizedText(ja: "撮影者不明"),
                    license: LocalizedText(ja: "パブリックドメイン")
                )
            )
        ]
        let ko = [Ko(
            kanji: "款冬華",
            reading: LocalizedText(ja: "ふきのはなさく"),
            gloss: "Butterbur blooms",
            sekkiId: "sekki-01",
            dateRange: DateRange(start: "01-01", end: "01-05"),  // does NOT cover 06-16
            description: LocalizedText(ja: "フキノトウが花を咲かせる。")
        )]
        let sekki = [Sekki(
            id: "sekki-01",
            kanji: "小寒",
            reading: LocalizedText(ja: "しょうかん"),
            gloss: LocalizedText(ja: "寒さの始まり"),
            description: LocalizedText(ja: "寒さが厳しくなる時期。")
        )]
        let manifest = Manifest(schemaVersion: "1.0", version: 1, dailyMap: dailyMap, ko: ko, sekki: sekki)
        let source = FakeContentSource(manifest: manifest)
        let june16 = FixedDateProvider(date: makeUTCDate(month: 6, day: 16))
        let store = ContentStore(source: source, dateProvider: june16)

        await store.waitForLoad()

        // Precondition: TodayResolver also can't resolve (no Ko covers 06-16)
        XCTAssertNil(
            store.todayResolved(),
            "Precondition: todayResolved() must be nil when no Ko contains 06-16 in the minimal manifest"
        )

        guard case .unavailablePlaceholder = store.screenState else {
            XCTFail("screenState must be .unavailablePlaceholder when AlmanacResolver returns nil for the date, got \(store.screenState)")
            return
        }
    }
}
