import XCTest
@testable import Kigo

// MARK: - ContentRootStateTests
//
// Slice #60: verifies the app root's content-state mapping.
//
// The mapping is exercised through `ContentStore.screenState` — a computed
// property that translates `ContentStore.state` into the `AppScreenState` enum,
// which the `ContentView` renders without any conditional logic of its own.
//
// Tests use in-process fakes (no UI, no simulator launch, no network) so they
// run fast and deterministically.

final class ContentRootStateTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a minimal `Manifest` with a single "01-01" entry, supporting
    /// Ko + Sekki resolution. Mirrors the helper in `ContentStoreTests`.
    private func makeManifest() -> Manifest {
        let dailyMap: [String: DailyMapEntry] = [
            "01-01": DailyMapEntry(
                kanji: "款冬華",
                reading: "ふきのはなさく",
                description: "Butterbur blooms.",
                imageId: "img-0101"
            )
        ]
        let ko = [Ko(
            kanji: "款冬華",
            reading: "ふきのはなさく",
            gloss: "Butterbur blooms",
            sekkiId: "sekki-01",
            dateRange: DateRange(start: "01-01", end: "01-05"),
            description: LocalizedText(ja: "フキノトウが花を咲かせる。")
        )]
        let sekki = [Sekki(id: "sekki-01", kanji: "小寒", reading: "しょうかん",
                           gloss: LocalizedText(ja: "寒さの始まり"),
                           description: LocalizedText(ja: "寒さが厳しくなる時期。"))]
        return Manifest(schemaVersion: "1.0", dailyMap: dailyMap, ko: ko, sekki: sekki)
    }

    // MARK: - AC1 & AC4: loading state → defined non-error placeholder

    /// When the content source is suspended (loading not yet complete), the store
    /// is in `.loading` and `screenState` maps to `.loadingPlaceholder`.
    ///
    /// This verifies AC1 (defined non-error placeholder shown while loading) and
    /// AC4 (the mapping is tested).
    @MainActor
    func testLoadingStateProducesLoadingPlaceholder() async throws {
        let source = HoldingFakeContentSource(manifest: makeManifest())
        let store = ContentStore(source: source)

        // Yield so the load task starts and suspends — store is in .loading.
        await Task.yield()

        guard case .loading = store.state else {
            XCTFail("Expected .loading state before source resumes, got \(store.state)")
            source.resume()
            return
        }

        // The app root mapping must produce .loadingPlaceholder (not crash, not empty).
        guard case .loadingPlaceholder = store.screenState else {
            XCTFail("screenState must be .loadingPlaceholder when store is in .loading, got \(store.screenState)")
            source.resume()
            return
        }

        // Clean up.
        source.resume()
        await store.waitForLoad()
    }

    // MARK: - AC2 & AC4: unavailable state → defined non-error placeholder

    /// When the content source always fails, the store enters `.unavailable` and
    /// `screenState` maps to `.unavailablePlaceholder`.
    ///
    /// This verifies AC2 (defined non-error state for unavailable, no crash) and
    /// AC4 (the mapping is tested).
    @MainActor
    func testUnavailableStateProducesUnavailablePlaceholder() async throws {
        let source = FailingContentSource()
        let store = ContentStore(source: source)

        await store.waitForLoad()

        guard case .unavailable = store.state else {
            XCTFail("Expected .unavailable state with failing source, got \(store.state)")
            return
        }

        // The app root mapping must produce .unavailablePlaceholder (not crash).
        guard case .unavailablePlaceholder = store.screenState else {
            XCTFail("screenState must be .unavailablePlaceholder when store is .unavailable, got \(store.screenState)")
            return
        }
    }

    // MARK: - AC3 & AC4: warm bundled path → Today screen

    /// After a successful load with an injected date that resolves a known day,
    /// `screenState` maps to `.today(ResolvedDay)` — confirming the warm bundled
    /// path still reaches the Today screen.
    ///
    /// This verifies AC3 (warm bundled path → Today screen) and AC4 (mapping tested).
    @MainActor
    func testLoadedStateProducesTodayScreen() async throws {
        let manifest = makeManifest()
        let source = FakeContentSource(manifest: manifest)
        // Pin to January 1 — the only date in the minimal manifest.
        let jan1 = FixedDateProvider(date: makeUTCDate(month: 1, day: 1))
        let store = ContentStore(source: source, dateProvider: jan1)

        await store.waitForLoad()

        guard case .loaded = store.state else {
            XCTFail("Expected .loaded state with fake source, got \(store.state)")
            return
        }

        // The app root mapping must produce .today with a resolved day.
        guard case .today(let resolved) = store.screenState else {
            XCTFail("screenState must be .today when store is .loaded and date resolves, got \(store.screenState)")
            return
        }

        XCTAssertEqual(
            resolved.kigoEntry.kanji,
            "款冬華",
            "screenState .today must carry the ResolvedDay for the injected date (款冬華 for 01-01)"
        )
    }

    // MARK: - AC2 & AC4: loaded but no entry for today → defined non-error state

    /// When the manifest is loaded but has no entry for the resolved date,
    /// `todayResolved()` returns nil. Waiting cannot fix a content gap, so the
    /// mapping must surface the defined non-error *terminal* state
    /// (`.unavailablePlaceholder`) — never an indefinite `.loadingPlaceholder`
    /// spinner that can never resolve.
    @MainActor
    func testLoadedWithNoEntryForTodayProducesUnavailablePlaceholder() async throws {
        let manifest = makeManifest() // only has a 01-01 entry
        let source = FakeContentSource(manifest: manifest)
        // Pin to a date the minimal manifest has no entry for.
        let june1 = FixedDateProvider(date: makeUTCDate(month: 6, day: 1))
        let store = ContentStore(source: source, dateProvider: june1)

        await store.waitForLoad()

        guard case .loaded = store.state else {
            XCTFail("Expected .loaded state with fake source, got \(store.state)")
            return
        }
        XCTAssertNil(store.todayResolved(), "Precondition: June 1 has no entry in the minimal manifest")

        // A loaded-but-unresolvable day is a terminal gap, not a transient load.
        guard case .unavailablePlaceholder = store.screenState else {
            XCTFail("screenState must be .unavailablePlaceholder when loaded with no entry for today, got \(store.screenState)")
            return
        }
    }

    // MARK: - Helpers

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
}
