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
                dateRange: DateRange(start: "01-01", end: "01-05")
            )
        ]
        let sekki = [
            Sekki(id: "sekki-01", kanji: "小寒", reading: "しょうかん")
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
}
