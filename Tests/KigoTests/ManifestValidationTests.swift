import XCTest
@testable import Kigo

final class ManifestValidationTests: XCTestCase {

    /// Loads the bundled manifest.json from the app bundle (Bundle.main, since KigoTests
    /// runs hosted in the Kigo app) and decodes it into the typed Manifest value type.
    /// This proves: committed JSON → bundled resource → decoded at runtime → typed content.
    func testBundledManifestDecodesWithNonEmptySchemaVersion() throws {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "manifest", withExtension: "json"),
            "manifest.json must be bundled in the Kigo app target — check project.yml resources"
        )
        let data = try Data(contentsOf: url)
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        XCTAssertFalse(
            manifest.schemaVersion.isEmpty,
            "Decoded Manifest must carry a non-empty schemaVersion"
        )
    }

    // MARK: - Daily Map coverage

    private func loadManifest() throws -> Manifest {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "manifest", withExtension: "json"),
            "manifest.json must be bundled in the Kigo app target"
        )
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    /// Acceptance criterion 1: exactly 366 distinct MM-DD keys including 02-29.
    func testDailyMapContainsExactly366Keys() throws {
        let manifest = try loadManifest()
        XCTAssertEqual(
            manifest.dailyMap.count,
            366,
            "dailyMap must contain exactly 366 MM-DD keys (all calendar days including 02-29)"
        )
    }

    func testDailyMapContainsLeapDay() throws {
        let manifest = try loadManifest()
        XCTAssertNotNil(
            manifest.dailyMap["02-29"],
            "dailyMap must include 02-29 (leap day)"
        )
    }

    /// Acceptance criterion 2: every entry has non-empty kanji and reading.
    func testEveryDailyMapEntryHasNonEmptyKanjiAndReading() throws {
        let manifest = try loadManifest()
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

    /// Acceptance criterion 3: every entry's description is ≥20 chars and imageId is non-empty.
    func testEveryDailyMapEntryHasDescriptionAndImageId() throws {
        let manifest = try loadManifest()
        for (key, entry) in manifest.dailyMap {
            XCTAssertGreaterThanOrEqual(
                entry.description.count,
                20,
                "Entry for \(key) has description shorter than 20 characters: '\(entry.description)'"
            )
            XCTAssertFalse(
                entry.imageId.isEmpty,
                "Entry for \(key) has empty imageId"
            )
        }
    }

    // MARK: - Kō and Sekki counts (slice #10)

    /// Acceptance criterion 1: exactly 72 Kō in the bundled manifest.
    func testManifestContainsExactly72Ko() throws {
        let manifest = try loadManifest()
        XCTAssertEqual(
            manifest.ko.count,
            72,
            "manifest.ko must contain exactly 72 Kō (got \(manifest.ko.count))"
        )
    }

    /// Acceptance criterion 1: exactly 24 Sekki in the bundled manifest.
    func testManifestContainsExactly24Sekki() throws {
        let manifest = try loadManifest()
        XCTAssertEqual(
            manifest.sekki.count,
            24,
            "manifest.sekki must contain exactly 24 Sekki (got \(manifest.sekki.count))"
        )
    }

    /// Acceptance criterion 2: every Kō has non-empty kanji, reading, and gloss.
    func testEveryKoHasNonEmptyKanjiReadingAndGloss() throws {
        let manifest = try loadManifest()
        for (index, ko) in manifest.ko.enumerated() {
            XCTAssertFalse(
                ko.kanji.isEmpty,
                "Kō at index \(index) has empty kanji"
            )
            XCTAssertFalse(
                ko.reading.isEmpty,
                "Kō at index \(index) has empty reading"
            )
            XCTAssertFalse(
                ko.gloss.isEmpty,
                "Kō at index \(index) has empty gloss"
            )
        }
    }

    /// Acceptance criterion 3: every Kō's sekkiId resolves to one of the 24 Sekki (referential integrity).
    func testEveryKoSekkiIdResolvesToAKnownSekki() throws {
        let manifest = try loadManifest()
        let sekkiIds = Set(manifest.sekki.map(\.id))
        XCTAssertEqual(
            sekkiIds.count,
            24,
            "manifest.sekki must have exactly 24 distinct ids (got \(sekkiIds.count))"
        )
        for (index, ko) in manifest.ko.enumerated() {
            XCTAssertTrue(
                sekkiIds.contains(ko.sekkiId),
                "Kō at index \(index) (\(ko.kanji)) has sekkiId '\(ko.sekkiId)' that does not match any Sekki id"
            )
        }
    }

    /// Validates the exact set of 366 MM-DD keys (all calendar days + 02-29).
    func testDailyMapContainsAllExpectedKeys() throws {
        let manifest = try loadManifest()

        // Build the expected 366 keys programmatically
        let calendar = Calendar(identifier: .gregorian)
        var expected = Set<String>()

        // Use 2000 as a leap year to cover 02-29
        var components = DateComponents()
        components.year = 2000
        let daysInMonth = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        for month in 1...12 {
            for day in 1...daysInMonth[month - 1] {
                components.month = month
                components.day = day
                let key = String(format: "%02d-%02d", month, day)
                expected.insert(key)
            }
        }
        // Verify we built exactly 366 expected keys
        XCTAssertEqual(expected.count, 366, "Test setup error: expected key set should have 366 items")

        let actual = Set(manifest.dailyMap.keys)
        let missing = expected.subtracting(actual)
        let extra = actual.subtracting(expected)

        XCTAssertTrue(
            missing.isEmpty,
            "dailyMap is missing these keys: \(missing.sorted().joined(separator: ", "))"
        )
        XCTAssertTrue(
            extra.isEmpty,
            "dailyMap has unexpected keys: \(extra.sorted().joined(separator: ", "))"
        )
        _ = calendar // suppress unused warning
    }
}
