import XCTest
@testable import Kigo

// MARK: - FakeContentSource

/// A test-only in-process fake `ContentSource` that returns a known `Manifest`
/// without any network, file I/O, or bundle access.
///
/// Using an in-memory fake (not a mock library) keeps the test fully self-contained
/// and verifies the store's behavior through its public API only.
struct FakeContentSource: ContentSource {
    let manifest: Manifest

    func load() async throws -> Manifest {
        return manifest
    }
}

// MARK: - HoldingFakeContentSource

/// A fake `ContentSource` that suspends until explicitly resumed.
/// Used to observe the `.loading` initial state before load completes.
///
/// Implemented with an `AsyncStream` continuation so no external synchronisation
/// primitive is needed — the store's Task suspends at `await source.load()` and
/// resumes only when `resume()` is called from the test.
final class HoldingFakeContentSource: ContentSource, @unchecked Sendable {
    private let manifest: Manifest
    private var continuation: AsyncStream<Void>.Continuation?
    private let stream: AsyncStream<Void>

    init(manifest: Manifest) {
        self.manifest = manifest
        var cap: AsyncStream<Void>.Continuation?
        self.stream = AsyncStream { cap = $0 }
        self.continuation = cap
    }

    /// Signals the suspended `load()` call to complete.
    func resume() {
        continuation?.yield(())
        continuation?.finish()
    }

    func load() async throws -> Manifest {
        // Suspend until resume() is called.
        for await _ in stream { break }
        return manifest
    }
}

// MARK: - CountingFakeContentSource

/// A test-only `ContentSource` that counts `load()` invocations.
/// The first call returns the provided `Manifest`; subsequent calls throw.
/// This lets tests assert that `todayEntry()` serves from cache without
/// re-invoking the source.
actor CountingFakeContentSource: ContentSource {
    let manifest: Manifest
    private(set) var loadCallCount: Int = 0

    init(manifest: Manifest) {
        self.manifest = manifest
    }

    func load() async throws -> Manifest {
        loadCallCount += 1
        if loadCallCount == 1 {
            return manifest
        }
        throw FailingContentSource.LoadFailure()
    }
}

// MARK: - ContentStoreTests

final class ContentStoreTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a minimal `Manifest` suitable for in-process testing.
    /// All required fields are present; counts differ from the real manifest
    /// so we can assert on the exact values we provided.
    private func makeManifest(schemaVersion: String = "1.0") -> Manifest {
        let dailyMap: [String: DailyMapEntry] = [
            "01-01": DailyMapEntry(
                kanji: "款冬華",
                reading: "ふきのはなさく",
                description: "Butterbur blooms.",
                imageId: "img-0101"
            )
        ]
        let ko = [
            Ko(
                kanji: "款冬華",
                reading: "ふきのはなさく",
                gloss: "Butterbur blooms",
                sekkiId: "sekki-01",
                dateRange: DateRange(start: "01-01", end: "01-05"),
                description: LocalizedText(ja: "フキノトウが花を咲かせる。")
            )
        ]
        let sekki = [
            Sekki(id: "sekki-01", kanji: "小寒", reading: "しょうかん",
                  gloss: LocalizedText(ja: "寒さの始まり"),
                  description: LocalizedText(ja: "寒さが厳しくなる時期。"))
        ]
        return Manifest(
            schemaVersion: schemaVersion,
            dailyMap: dailyMap,
            ko: ko,
            sekki: sekki
        )
    }

    // MARK: - Criterion 1: State shape

    /// The store exposes a `ContentState` with three cases; initial state is `.loading`.
    ///
    /// Because the store kicks off a `Task` on init and Swift's cooperative scheduler
    /// may run it before we read `state`, this test uses `HoldingFakeContentSource`
    /// which suspends until explicitly resumed — guaranteeing we can observe `.loading`.
    @MainActor
    func testInitialStateIsLoading() async throws {
        let source = HoldingFakeContentSource(manifest: makeManifest())
        let store = ContentStore(source: source)

        // Yield to the scheduler so the store's Task starts and suspends in load().
        await Task.yield()

        // Before we resume the source, the store must be in .loading.
        guard case .loading = store.state else {
            XCTFail("Initial state must be .loading before load completes, got \(store.state)")
            source.resume()
            return
        }

        // Clean up: let the source complete so the Task finishes.
        source.resume()
        await store.waitForLoad()
    }

    // MARK: - Criterion 2: Happy-path load transitions to .loaded

    /// After a successful source load, state is `.loaded` carrying the same `Manifest`.
    @MainActor
    func testLoadTransitionsToLoadedWithManifest() async throws {
        let expected = makeManifest(schemaVersion: "2.0-test")
        let source = FakeContentSource(manifest: expected)
        let store = ContentStore(source: source)

        // Wait for the in-flight load (triggered on init) to complete.
        await store.waitForLoad()

        guard case .loaded(let manifest) = store.state else {
            XCTFail("Expected .loaded after successful source, got \(store.state)")
            return
        }

        // Assert equality on stable fields.
        // Manifest is Equatable (conformance added in Manifest.swift); prefer that.
        XCTAssertEqual(manifest, expected,
            "Loaded manifest must equal the manifest returned by the ContentSource")
    }

    // MARK: - Criterion 3: Non-throwing public API

    /// `ContentStore`'s public API is non-throwing: no `Error` escapes to the caller.
    ///
    /// This is a compile-time criterion (verified by the fact that `waitForLoad()`
    /// and `state` are not marked `throws` and there is no `try` here). The test
    /// simply exercises the path; if it compiles it confirms the API contract.
    @MainActor
    func testPublicAPIIsNonThrowing() async {
        let source = FakeContentSource(manifest: makeManifest())
        let store = ContentStore(source: source)
        await store.waitForLoad()

        // No `try` required — the public API is non-throwing.
        let _ = store.state
    }

    // MARK: - Criterion 4: In-process fake exercises the loaded path

    /// Exercises the full loaded path using an in-process fake (no network, no bundle).
    @MainActor
    func testInProcessFakeExercisesLoadedPath() async throws {
        let manifest = makeManifest()
        let source = FakeContentSource(manifest: manifest)
        let store = ContentStore(source: source)

        await store.waitForLoad()

        guard case .loaded(let loaded) = store.state else {
            XCTFail("In-process fake must produce .loaded state, got \(store.state)")
            return
        }

        XCTAssertEqual(loaded.schemaVersion, manifest.schemaVersion)
        XCTAssertEqual(loaded.dailyMap.count, manifest.dailyMap.count)
        XCTAssertEqual(loaded.ko.count, manifest.ko.count)
        XCTAssertEqual(loaded.sekki.count, manifest.sekki.count)
    }

    // MARK: - Criterion 5 (slice #21): DateProvider seam + todayEntry()

    /// AC1: A FixedDateProvider injected with 2024-01-01 produces a day-key of "01-01"
    /// and todayEntry() returns the dailyMap entry for that key from the loaded manifest.
    @MainActor
    func testTodayEntryReturnsCorrectEntryForInjectedDate() async throws {
        // The fake manifest has a "01-01" entry.
        let manifest = makeManifest()
        let source = FakeContentSource(manifest: manifest)
        // January 1 UTC → day-key "01-01"
        let jan1 = FixedDateProvider(date: makeUTCDate(month: 1, day: 1))
        let store = ContentStore(source: source, dateProvider: jan1)

        await store.waitForLoad()

        let entry = store.todayEntry()
        XCTAssertNotNil(entry, "todayEntry() must return a non-nil entry for a known day-key")
        XCTAssertEqual(entry?.kanji, "款冬華", "Entry for 01-01 must have kanji 款冬華")
    }

    // MARK: - Criterion 6 (slice #21): Offline survival — cache hit with failing source

    /// AC2/AC3: After one successful load warms the cache, replacing the source with an
    /// always-failing one still yields today's entry from cache — no error, no source call.
    ///
    /// Implementation: todayEntry() reads only from `.loaded(Manifest)` and never calls
    /// source.load(). So we verify (a) the entry is returned, (b) state is still .loaded
    /// (not .unavailable), and (c) the load count from the source is exactly 1 (the initial
    /// warm-up call, not a subsequent one when serving today's entry).
    @MainActor
    func testOfflineSurvival_cacheHitRequiresNoSourceCall() async throws {
        let manifest = makeManifest()
        // CountingFakeContentSource fails after the first call so we can detect re-calls.
        let source = CountingFakeContentSource(manifest: manifest)
        let jan1 = FixedDateProvider(date: makeUTCDate(month: 1, day: 1))
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

        // Now call todayEntry() — must return the cached entry without calling source again.
        let entry = store.todayEntry()
        XCTAssertNotNil(entry, "todayEntry() must return a non-nil entry from cache")
        XCTAssertEqual(entry?.kanji, "款冬華")

        // Store state is still .loaded — not .unavailable.
        guard case .loaded = store.state else {
            XCTFail("Store state must remain .loaded after serving from cache, got \(store.state)")
            return
        }

        // Source must not have been called again.
        let callsAfterServing = await source.loadCallCount
        XCTAssertEqual(callsAfterServing, 1,
            "todayEntry() must not call source.load(); extra call count: \(callsAfterServing - 1)")
    }

    // MARK: - Criterion 7 (slice #21): todayEntry() returns nil before load completes

    /// Confirms todayEntry() returns nil while state is still .loading (cache not yet warm).
    @MainActor
    func testTodayEntryIsNilWhileLoading() async throws {
        let source = HoldingFakeContentSource(manifest: makeManifest())
        let jan1 = FixedDateProvider(date: makeUTCDate(month: 1, day: 1))
        let store = ContentStore(source: source, dateProvider: jan1)

        // Yield so the load task starts and suspends inside source.load().
        await Task.yield()

        // Before the source resumes, cache is cold — todayEntry() must return nil.
        XCTAssertNil(store.todayEntry(), "todayEntry() must be nil while state is .loading")

        // Clean up.
        source.resume()
        await store.waitForLoad()
    }

    // MARK: - Criterion 8 (slice #55): AC4 — todayResolved() uses the injected DateProvider

    /// AC4: The composition resolves through the injected DateProvider, not a raw Date().
    ///
    /// Injects a FixedDateProvider for a known date (January 1) and asserts that
    /// `store.todayResolved()` returns the matching ResolvedDay from the loaded manifest —
    /// proving resolution flows through the seam rather than bypassing it with Date().
    @MainActor
    func testTodayResolvedUsesInjectedDateProvider() async throws {
        // The fake manifest has a "01-01" entry with full Ko+Sekki data for resolution.
        let manifest = makeManifest()
        let source = FakeContentSource(manifest: manifest)
        // Fix the date to January 1 — the only date present in the fake manifest.
        let jan1 = FixedDateProvider(date: makeUTCDate(month: 1, day: 1))
        let store = ContentStore(source: source, dateProvider: jan1)

        await store.waitForLoad()

        let resolved = store.todayResolved()
        XCTAssertNotNil(resolved, "todayResolved() must return a non-nil ResolvedDay for a known day")
        XCTAssertEqual(
            resolved?.kigoEntry.kanji, "款冬華",
            "todayResolved() must resolve the entry for the injected DateProvider's date (01-01 → 款冬華)"
        )
    }

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
}
