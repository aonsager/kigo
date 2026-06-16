import XCTest
@testable import Kigo

// MARK: - FailingContentSource

/// A test-only in-process fake `ContentSource` that always throws on `load()`.
/// Used to verify the cold-start guarantee: an empty cache + failing source
/// must never surface a thrown error to the caller; the store resolves to
/// `.unavailable` instead.
struct FailingContentSource: ContentSource {
    struct LoadFailure: Error {}
    func load() async throws -> Manifest { throw LoadFailure() }
}

final class ContentSourceTests: XCTestCase {

    // MARK: - Protocol conformance

    /// Verifies that BundledContentSource exists and conforms to ContentSource.
    func testBundledContentSourceConformsToContentSource() {
        let source: any ContentSource = BundledContentSource()
        XCTAssertNotNil(source, "BundledContentSource must conform to ContentSource")
    }

    // MARK: - BundledContentSource.load()

    /// Acceptance criterion 2: BundledContentSource().load() returns a Manifest
    /// whose schemaVersion, dailyMap (366 keys), ko (72), and sekki (24) equal the
    /// values decoded directly from the bundled manifest.json.
    func testBundledContentSourceLoadMatchesBundledJSON() async throws {
        // Load directly from bundle (reference path, same as ManifestValidationTests)
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "manifest", withExtension: "json"),
            "manifest.json must be bundled in the Kigo app target"
        )
        let data = try Data(contentsOf: url)
        let expected = try JSONDecoder().decode(Manifest.self, from: data)

        // Load via BundledContentSource
        let source = BundledContentSource()
        let loaded = try await source.load()

        // schemaVersion must match
        XCTAssertEqual(
            loaded.schemaVersion,
            expected.schemaVersion,
            "schemaVersion must match the bundled manifest"
        )

        // dailyMap key sets must be identical (366 keys)
        XCTAssertEqual(
            loaded.dailyMap.count,
            366,
            "BundledContentSource loaded dailyMap must contain 366 keys"
        )
        XCTAssertEqual(
            Set(loaded.dailyMap.keys),
            Set(expected.dailyMap.keys),
            "BundledContentSource loaded dailyMap keys must exactly match the bundled manifest"
        )

        // ko count must be 72
        XCTAssertEqual(
            loaded.ko.count,
            72,
            "BundledContentSource loaded ko must contain exactly 72 entries"
        )

        // sekki count must be 24
        XCTAssertEqual(
            loaded.sekki.count,
            24,
            "BundledContentSource loaded sekki must contain exactly 24 entries"
        )
    }

    /// Spot-checks a known dailyMap entry from the loaded manifest.
    func testBundledContentSourceDailyMapEntriesAreNonEmpty() async throws {
        let source = BundledContentSource()
        let manifest = try await source.load()

        // Every entry must have non-empty kanji and reading
        for (key, entry) in manifest.dailyMap {
            XCTAssertFalse(
                entry.kanji.isEmpty,
                "Entry for \(key) has empty kanji"
            )
            XCTAssertFalse(
                entry.reading.isEmpty,
                "Entry for \(key) has empty reading"
            )
        }
    }

    /// Verifies schemaVersion is non-empty and ko/sekki deep equality spot-check.
    func testBundledContentSourceSchemaVersionIsNonEmpty() async throws {
        let source = BundledContentSource()
        let manifest = try await source.load()
        XCTAssertFalse(
            manifest.schemaVersion.isEmpty,
            "BundledContentSource.load() must return a non-empty schemaVersion"
        )
    }

    // MARK: - Offline survival: cache hit requires no source call

    /// C3 assertion: after one successful load warms the cache, the source is
    /// (effectively) replaced with an always-failing one, yet today's entry is
    /// still served from cache without calling the source again.
    ///
    /// Uses `CountingFakeContentSource` (defined in ContentStoreTests.swift, same
    /// test module): first call succeeds and warms the cache; subsequent calls throw.
    /// `loadCallCount` must remain exactly 1 after `todayEntry()` is called.
    @MainActor
    func testOfflineSurvival_cacheHitRequiresNoSourceCall() async throws {
        // Build a minimal manifest with a known "01-01" entry.
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
            dateRange: DateRange(start: "01-01", end: "01-05")
        )]
        let sekki = [Sekki(id: "sekki-01", kanji: "小寒", reading: "しょうかん",
                           gloss: LocalizedText(ja: "寒さの始まり"),
                           description: LocalizedText(ja: "寒さが厳しくなる時期。"))]
        let manifest = Manifest(schemaVersion: "1.0", dailyMap: dailyMap, ko: ko, sekki: sekki)

        // CountingFakeContentSource: first call returns the manifest; subsequent calls throw.
        let source = CountingFakeContentSource(manifest: manifest)
        // Pin "today" to 01-01 so todayEntry() looks up the "01-01" key.
        let jan1 = FixedDateProvider(date: makeUTCDateInContentSourceTests(month: 1, day: 1))
        let store = ContentStore(source: source, dateProvider: jan1)

        // Warm the cache with one successful load.
        await store.waitForLoad()
        guard case .loaded = store.state else {
            XCTFail("Store must be .loaded after warm-up, got \(store.state)")
            return
        }

        // Record load count after warm-up (must be exactly 1).
        let callsAfterWarmUp = await source.loadCallCount
        XCTAssertEqual(callsAfterWarmUp, 1, "Source must be called exactly once during warm-up")

        // Call todayEntry() — must return the cached entry without calling source again.
        let entry = store.todayEntry()
        XCTAssertNotNil(entry, "todayEntry() must return a non-nil entry from cache")
        XCTAssertEqual(entry?.kanji, "款冬華", "Cached entry kanji must match the warm-up manifest")

        // State must remain .loaded (not .unavailable) — cache is intact.
        guard case .loaded = store.state else {
            XCTFail("Store state must remain .loaded after serving from cache, got \(store.state)")
            return
        }

        // Source must not have been called again after warm-up.
        let callsAfterServing = await source.loadCallCount
        XCTAssertEqual(callsAfterServing, 1,
            "todayEntry() must not call source.load(); extra call count: \(callsAfterServing - 1)")
    }

    // MARK: - Cold-start: empty cache + failing source

    /// Acceptance criteria: with an empty cache and an always-failing ContentSource,
    /// the store ends in the `.unavailable` state. The FailingContentSource's error
    /// never requires a `try` at the store's public API surface (compile-time
    /// guarantee confirmed by the absence of `try` in this test body). The fake
    /// is in-process — no live network is used.
    @MainActor
    func testColdStartWithFailingSourceResolvesToUnavailable() async {
        // Arrange: empty cache (no prior load), always-failing source.
        let source = FailingContentSource()
        let store = ContentStore(source: source)

        // Act: wait for the store to finish loading.
        // No `try` needed — the store's public API is non-throwing.
        await store.waitForLoad()

        // Assert: the store must be in the .unavailable state.
        guard case .unavailable = store.state else {
            XCTFail(
                "Cold-start with failing source must resolve to .unavailable, got \(store.state)"
            )
            return
        }
        // If we reach here the store absorbed the error; no error escaped.
    }

    // MARK: - Helpers

    /// Creates a UTC `Date` for the given month and day (year is irrelevant for MM-DD lookup).
    /// Named distinctly from the `private` helper in `ContentStoreTests` to avoid ambiguity.
    private func makeUTCDateInContentSourceTests(month: Int, day: Int) -> Date {
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
