import XCTest
@testable import Kigo

// MARK: - ContentLocalizationCompletenessTests
//
// Slice #166: Verifies that every Daily Map entry loaded through BundledContentSource
// has non-empty English localization fields with no CJK characters in reading/description.

final class ContentLocalizationCompletenessTests: XCTestCase {

    private func loadManifest() throws -> Manifest {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "manifest", withExtension: "json"),
            "manifest.json must be bundled in the Kigo app target — check project.yml resources"
        )
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    // MARK: - CJK check helper

    /// Fails if `s` is empty OR contains any hiragana, katakana, or CJK unified ideograph
    /// scalar (U+3040–U+30FF, U+3400–U+9FFF, U+FF66–U+FF9F).
    private func assertNoCJK(_ s: String, _ message: String, file: StaticString = #file, line: UInt = #line) {
        XCTAssertFalse(s.isEmpty, "Expected non-empty string but got empty: \(message)", file: file, line: line)
        for scalar in s.unicodeScalars {
            let v = scalar.value
            let isCJK = (v >= 0x3040 && v <= 0x30FF)   // hiragana + katakana
                     || (v >= 0x3400 && v <= 0x9FFF)   // CJK unified + ext A
                     || (v >= 0xFF66 && v <= 0xFF9F)   // halfwidth katakana
            XCTAssertFalse(isCJK,
                "String contains CJK character U+\(String(v, radix: 16, uppercase: true)) in: \(message)",
                file: file, line: line)
        }
    }

    // MARK: - reading.en

    /// Every daily map entry's reading.en is non-empty and contains no CJK characters.
    func testAllEntriesReadingEnIsRomaji() throws {
        let manifest = try loadManifest()
        for (key, entry) in manifest.dailyMap {
            guard let readingEn = entry.reading.en else {
                XCTFail("Entry \(key) has nil reading.en")
                continue
            }
            assertNoCJK(readingEn, "reading.en for entry \(key)")
        }
    }

    // MARK: - description.en

    /// Every daily map entry's description.en is non-empty, contains no CJK characters,
    /// and contains a date-like substring matching YYYY-MM-DD.
    func testAllEntriesDescriptionEnIsEnglishWithDate() throws {
        let manifest = try loadManifest()
        let datePattern = try NSRegularExpression(pattern: #"\d{4}-\d{2}-\d{2}"#)
        for (key, entry) in manifest.dailyMap {
            guard let descEn = entry.description.en else {
                XCTFail("Entry \(key) has nil description.en")
                continue
            }
            assertNoCJK(descEn, "description.en for entry \(key)")
            let range = NSRange(descEn.startIndex..., in: descEn)
            let hasDate = datePattern.firstMatch(in: descEn, range: range) != nil
            XCTAssertTrue(hasDate,
                "description.en for entry \(key) has no YYYY-MM-DD date: \"\(descEn)\"")
        }
    }

    // MARK: - attribution.title.en

    /// Every daily map entry's attribution title.en exactly equals "Season Kigo".
    func testAllEntriesAttributionTitleEnIsSeasonKigo() throws {
        let manifest = try loadManifest()
        for (key, entry) in manifest.dailyMap {
            XCTAssertEqual(entry.attribution.title.en, "Season Kigo",
                "Entry \(key) attribution.title.en mismatch")
        }
    }

    // MARK: - attribution.credit.en

    /// Every daily map entry's attribution credit.en exactly equals "Unknown photographer".
    func testAllEntriesAttributionCreditEnIsUnknownPhotographer() throws {
        let manifest = try loadManifest()
        for (key, entry) in manifest.dailyMap {
            XCTAssertEqual(entry.attribution.credit.en, "Unknown photographer",
                "Entry \(key) attribution.credit.en mismatch")
        }
    }

    // MARK: - attribution.license.en

    /// Every daily map entry's attribution license.en exactly equals "Public domain".
    func testAllEntriesAttributionLicenseEnIsPublicDomain() throws {
        let manifest = try loadManifest()
        for (key, entry) in manifest.dailyMap {
            XCTAssertEqual(entry.attribution.license.en, "Public domain",
                "Entry \(key) attribution.license.en mismatch")
        }
    }

    // MARK: - kanji stability

    /// The kanji field is not a LocalizedText — it's a plain String. Verify it is
    /// non-empty for every entry after loading the manifest.
    func testKanjiIsStableAcrossEntries() throws {
        let manifest = try loadManifest()
        for (key, entry) in manifest.dailyMap {
            XCTAssertFalse(entry.kanji.isEmpty,
                "Entry \(key) has empty kanji")
        }
    }

    // MARK: - Kō reading.en

    /// Every kō's reading.en is non-empty and contains no CJK characters (Hepburn romaji).
    func testAllKoReadingEnIsRomaji() throws {
        let manifest = try loadManifest()
        XCTAssertEqual(manifest.ko.count, 72, "Expected 72 kō entries in the manifest")
        for ko in manifest.ko {
            guard let readingEn = ko.reading.en else {
                XCTFail("Kō \(ko.kanji) has nil reading.en")
                continue
            }
            assertNoCJK(readingEn, "reading.en for kō \(ko.kanji)")
        }
    }

    // MARK: - Kō description.en

    /// Every kō's description.en is non-empty and contains no CJK characters.
    func testAllKoDescriptionEnIsEnglish() throws {
        let manifest = try loadManifest()
        XCTAssertEqual(manifest.ko.count, 72, "Expected 72 kō entries in the manifest")
        for ko in manifest.ko {
            guard let descEn = ko.description.en else {
                XCTFail("Kō \(ko.kanji) has nil description.en")
                continue
            }
            assertNoCJK(descEn, "description.en for kō \(ko.kanji)")
        }
    }

    // MARK: - fallback behaviour when only ja is present

    /// Construct a DailyMapEntry JSON with only ja values (no en keys), decode it,
    /// and verify: decode succeeds, .en is nil, and (field.en ?? field.ja) == field.ja.
    func testEnglishAbsentEntryDecodesAndFallsBack() throws {
        let jsonString = """
        {
          "kanji": "梅",
          "reading": { "ja": "うめ" },
          "description": { "ja": "Plum blossom." },
          "imageId": "test-image",
          "attribution": {
            "title": { "ja": "梅の花" },
            "credit": { "ja": "撮影者不明" },
            "license": { "ja": "パブリックドメイン" }
          }
        }
        """
        let data = Data(jsonString.utf8)
        let entry = try JSONDecoder().decode(DailyMapEntry.self, from: data)

        // Decode succeeds — we get here
        XCTAssertEqual(entry.kanji, "梅")

        // .en is nil for all LocalizedText fields
        XCTAssertNil(entry.reading.en, "reading.en should be nil when absent in JSON")
        XCTAssertNil(entry.description.en, "description.en should be nil when absent in JSON")
        XCTAssertNil(entry.attribution.title.en, "attribution.title.en should be nil when absent in JSON")
        XCTAssertNil(entry.attribution.credit.en, "attribution.credit.en should be nil when absent in JSON")
        XCTAssertNil(entry.attribution.license.en, "attribution.license.en should be nil when absent in JSON")

        // (field.en ?? field.ja) falls back to field.ja
        XCTAssertEqual(entry.reading.en ?? entry.reading.ja, entry.reading.ja)
        XCTAssertEqual(entry.description.en ?? entry.description.ja, entry.description.ja)
        XCTAssertEqual(entry.attribution.title.en ?? entry.attribution.title.ja, entry.attribution.title.ja)
    }
}
