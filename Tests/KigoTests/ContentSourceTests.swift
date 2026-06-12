import XCTest
@testable import Kigo

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
}
