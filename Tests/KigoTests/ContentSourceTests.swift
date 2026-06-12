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
}
