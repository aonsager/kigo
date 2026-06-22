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

    /// Acceptance criterion 1: exactly 365 absolute 2026-MM-DD keys (2026 is not a leap year).
    func testDailyMapContainsExactly365Keys() throws {
        let manifest = try loadManifest()
        XCTAssertEqual(
            manifest.dailyMap.count,
            365,
            "dailyMap must contain exactly 365 absolute 2026-MM-DD keys (every day of 2026)"
        )
    }

    /// 2026 is not a leap year, so the absolute daily map must NOT contain 2026-02-29.
    func testDailyMapExcludesNonexistentLeapDay() throws {
        let manifest = try loadManifest()
        XCTAssertNil(
            manifest.dailyMap["2026-02-29"],
            "dailyMap must not include 2026-02-29 (2026 is not a leap year)"
        )
    }

    /// Every daily-map key is a well-formed absolute 2026-MM-DD string.
    func testEveryDailyMapKeyIsAbsolute2026Date() throws {
        let manifest = try loadManifest()
        for key in manifest.dailyMap.keys {
            XCTAssertNotNil(
                key.range(of: #"^2026-\d{2}-\d{2}$"#, options: .regularExpression),
                "dailyMap key '\(key)' must be an absolute 2026-MM-DD date"
            )
        }
    }

    /// Acceptance criterion 2: every entry has non-empty kanji and a LocalizedText reading with non-empty ja.
    func testEveryDailyMapEntryHasNonEmptyKanjiAndReading() throws {
        let manifest = try loadManifest()
        for (key, entry) in manifest.dailyMap {
            XCTAssertFalse(
                entry.kanji.isEmpty,
                "Entry for \(key) has empty kanji"
            )
            XCTAssertFalse(
                entry.reading.ja.isEmpty,
                "Entry for \(key) has empty reading.ja"
            )
        }
    }

    /// Acceptance criterion 3: every entry's description.ja is ≥20 chars, stamped with its own
    /// absolute date (the C4 instrumentation), and imageId is non-empty.
    func testEveryDailyMapEntryHasDescriptionAndImageId() throws {
        let manifest = try loadManifest()
        for (key, entry) in manifest.dailyMap {
            XCTAssertGreaterThanOrEqual(
                entry.description.ja.count,
                20,
                "Entry for \(key) has description.ja shorter than 20 characters: '\(entry.description.ja)'"
            )
            XCTAssertTrue(
                entry.description.ja.contains(key),
                "Entry for \(key) must stamp its absolute date into description.ja: '\(entry.description.ja)'"
            )
            XCTAssertFalse(
                entry.imageId.isEmpty,
                "Entry for \(key) has empty imageId"
            )
        }
    }

    /// The manifest carries both a non-empty schemaVersion and an integer content version.
    func testManifestCarriesSchemaVersionAndIntegerVersion() throws {
        let manifest = try loadManifest()
        XCTAssertFalse(manifest.schemaVersion.isEmpty, "schemaVersion must be present and non-empty")
        XCTAssertGreaterThanOrEqual(manifest.version, 1, "content version must be a positive integer")
    }

    /// Acceptance criterion (slice #100): every entry has non-empty attribution title, credit, and license.
    func testEveryDailyMapEntryHasNonEmptyAttribution() throws {
        let manifest = try loadManifest()
        for (key, entry) in manifest.dailyMap {
            XCTAssertFalse(
                entry.attribution.title.ja.isEmpty,
                "Entry for \(key) has empty attribution.title.ja"
            )
            XCTAssertFalse(
                entry.attribution.credit.ja.isEmpty,
                "Entry for \(key) has empty attribution.credit.ja"
            )
            XCTAssertFalse(
                entry.attribution.license.ja.isEmpty,
                "Entry for \(key) has empty attribution.license.ja"
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
                ko.reading.ja.isEmpty,
                "Kō at index \(index) has empty reading.ja"
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

    // MARK: - Kō tiling (slice #11)

    /// All 366 calendar days (MM-DD, including 02-29) fall within exactly one Kō range.
    /// The year is modeled as the linear span 01-01..12-31 (leap year: 366 days).
    /// 02-29 is explicitly required to fall inside exactly one Kō.
    func testKoRangesTileEntireYear() throws {
        let manifest = try loadManifest()

        // Build the ordered list of all 366 MM-DD strings for a leap year.
        let daysInMonth = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        var allDays: [String] = []
        for month in 1...12 {
            for day in 1...daysInMonth[month - 1] {
                allDays.append(String(format: "%02d-%02d", month, day))
            }
        }
        XCTAssertEqual(allDays.count, 366, "Test setup: should produce 366 days")

        // Map each MM-DD to its 0-based index in the leap-year sequence.
        let dayIndex: [String: Int] = Dictionary(
            uniqueKeysWithValues: allDays.enumerated().map { ($1, $0) }
        )

        // Count how many Kō cover each day.
        var coverage = [Int](repeating: 0, count: 366)
        for (koIndex, ko) in manifest.ko.enumerated() {
            let startKey = ko.dateRange.start
            let endKey = ko.dateRange.end
            guard let si = dayIndex[startKey], let ei = dayIndex[endKey] else {
                XCTFail("Kō \(koIndex) (\(ko.kanji)) has dateRange \(startKey)–\(endKey) with an unrecognised MM-DD key")
                continue
            }
            XCTAssertLessThanOrEqual(
                si, ei,
                "Kō \(koIndex) (\(ko.kanji)) has start \(startKey) after end \(endKey) — cross-year spans are not supported"
            )
            if si <= ei {
                for i in si...ei { coverage[i] += 1 }
            }
        }

        // Every day must be covered by exactly one Kō.
        var uncovered: [String] = []
        var overlapping: [String] = []
        for (i, day) in allDays.enumerated() {
            if coverage[i] == 0 { uncovered.append(day) }
            if coverage[i] > 1 { overlapping.append(day) }
        }

        XCTAssertTrue(
            uncovered.isEmpty,
            "Days not covered by any Kō: \(uncovered.joined(separator: ", "))"
        )
        XCTAssertTrue(
            overlapping.isEmpty,
            "Days covered by more than one Kō: \(overlapping.joined(separator: ", "))"
        )

        // Explicitly assert 02-29 is covered (leap day must not be a gap).
        let leapDayIndex = dayIndex["02-29"]!
        XCTAssertEqual(
            coverage[leapDayIndex],
            1,
            "02-29 (leap day) must fall within exactly one Kō (coverage count: \(coverage[leapDayIndex]))"
        )
    }

    /// Validates the exact set of 365 absolute 2026-MM-DD keys (every day of 2026, no 02-29).
    func testDailyMapContainsAllExpectedKeys() throws {
        let manifest = try loadManifest()

        // Build the expected 365 absolute keys for 2026 (a non-leap year).
        var expected = Set<String>()
        let daysInMonth = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        for month in 1...12 {
            for day in 1...daysInMonth[month - 1] {
                expected.insert(String(format: "2026-%02d-%02d", month, day))
            }
        }
        XCTAssertEqual(expected.count, 365, "Test setup error: expected key set should have 365 items")

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
    }
}
