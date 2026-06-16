import XCTest
@testable import Kigo

// MARK: - LocalizableContentTests
//
// Slice #98: Pins the forward-compatible decode shape for LocalizedText.
//
// These tests verify that a Manifest field using the LocalizedText shape decodes:
//   - with only the required Japanese value present (no "en" key)
//   - with both the Japanese and optional English values present
//
// Both cases must round-trip: re-encoding the decoded value and decoding again
// yields the same LocalizedText. This prevents a later EN content rollout from
// silently breaking the decode shape.

final class LocalizableContentTests: XCTestCase {

    // MARK: - Decode shape: Japanese only (no "en" key)

    /// A JSON object with only a "ja" key must decode successfully into LocalizedText,
    /// and the decoded value must carry the Japanese string with nil English.
    func testDecodesWithJapanesOnlyNoEnglishKey() throws {
        let json = #"{"ja": "立春の始まり"}"#
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(LocalizedText.self, from: data)
        XCTAssertEqual(decoded.ja, "立春の始まり",
                       "Japanese value must match the input")
        XCTAssertNil(decoded.en,
                     "English value must be nil when 'en' key is absent")
    }

    /// A JSON object with both "ja" and "en" keys must decode successfully,
    /// carrying both values.
    func testDecodesWithBothJapaneseAndEnglish() throws {
        let json = #"{"ja": "立春の始まり", "en": "The beginning of spring"}"#
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(LocalizedText.self, from: data)
        XCTAssertEqual(decoded.ja, "立春の始まり",
                       "Japanese value must match the input")
        XCTAssertEqual(decoded.en, "The beginning of spring",
                       "English value must match the input when present")
    }

    // MARK: - Round-trip: Japanese only

    /// Encoding a Japanese-only LocalizedText and re-decoding must yield the same value.
    func testRoundTripJapaneseOnly() throws {
        let original = LocalizedText(ja: "二十四節気のひとつ", en: nil)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LocalizedText.self, from: encoded)
        XCTAssertEqual(decoded, original,
                       "Round-trip (Japanese only) must produce an equal LocalizedText")
        XCTAssertNil(decoded.en,
                     "Re-decoded English must remain nil when original had none")
    }

    /// Encoding a LocalizedText with both values and re-decoding must yield the same value.
    func testRoundTripWithEnglish() throws {
        let original = LocalizedText(ja: "二十四節気のひとつ", en: "One of the 24 solar terms")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LocalizedText.self, from: encoded)
        XCTAssertEqual(decoded, original,
                       "Round-trip (with English) must produce an equal LocalizedText")
        XCTAssertEqual(decoded.ja, original.ja,
                       "Japanese value must survive the round-trip unchanged")
        XCTAssertEqual(decoded.en, original.en,
                       "English value must survive the round-trip unchanged")
    }

    // MARK: - Sekki fixture: decodes with and without English

    /// A Sekki JSON fixture carrying LocalizedText for gloss and description
    /// must decode whether or not the English keys are present — proving the
    /// optional-English shape works end-to-end in the Sekki struct.
    func testSekkiDecodesWithoutEnglishFields() throws {
        let json = """
        {
          "id": "risshun",
          "kanji": "立春",
          "reading": "りっしゅん",
          "gloss": {"ja": "春の始まり"},
          "description": {"ja": "太陽が黄経315度に達する日。春の気配が感じられる。"}
        }
        """
        let data = Data(json.utf8)
        let sekki = try JSONDecoder().decode(Sekki.self, from: data)
        XCTAssertEqual(sekki.id, "risshun")
        XCTAssertEqual(sekki.gloss.ja, "春の始まり")
        XCTAssertNil(sekki.gloss.en,
                     "gloss.en must be nil when absent in JSON")
        XCTAssertEqual(sekki.description.ja, "太陽が黄経315度に達する日。春の気配が感じられる。")
        XCTAssertNil(sekki.description.en,
                     "description.en must be nil when absent in JSON")
    }

    func testSekkiDecodesWithEnglishFields() throws {
        let json = """
        {
          "id": "risshun",
          "kanji": "立春",
          "reading": "りっしゅん",
          "gloss": {"ja": "春の始まり", "en": "Beginning of spring"},
          "description": {"ja": "太陽が黄経315度に達する日。春の気配が感じられる。", "en": "The day the sun reaches 315° ecliptic longitude. Signs of spring begin to appear."}
        }
        """
        let data = Data(json.utf8)
        let sekki = try JSONDecoder().decode(Sekki.self, from: data)
        XCTAssertEqual(sekki.gloss.en, "Beginning of spring",
                       "gloss.en must be decoded when present")
        XCTAssertEqual(sekki.description.en, "The day the sun reaches 315° ecliptic longitude. Signs of spring begin to appear.",
                       "description.en must be decoded when present")
        // Japanese values must also survive
        XCTAssertEqual(sekki.gloss.ja, "春の始まり")
        XCTAssertEqual(sekki.description.ja, "太陽が黄経315度に達する日。春の気配が感じられる。")
    }

    // MARK: - Ko fixture: description decodes with and without English (slice #99)

    /// A Ko JSON fixture carrying LocalizedText for description must decode
    /// when only the required Japanese value is present.
    func testKoDecodesWithJapaneseOnlyDescription() throws {
        let json = """
        {
          "kanji": "東風解凍",
          "reading": "はるかぜこおりをとく",
          "gloss": "east wind thaws the ice",
          "sekkiId": "risshun",
          "dateRange": {"start": "02-04", "end": "02-08"},
          "description": {"ja": "春の東風が氷を解かし始める。"}
        }
        """
        let data = Data(json.utf8)
        let ko = try JSONDecoder().decode(Ko.self, from: data)
        XCTAssertEqual(ko.kanji, "東風解凍")
        XCTAssertEqual(ko.description.ja, "春の東風が氷を解かし始める。",
                       "description.ja must match the input")
        XCTAssertNil(ko.description.en,
                     "description.en must be nil when 'en' key is absent")
    }

    /// A Ko JSON fixture with both Japanese and English description values must decode both.
    func testKoDecodesWithBothJapaneseAndEnglishDescription() throws {
        let json = """
        {
          "kanji": "東風解凍",
          "reading": "はるかぜこおりをとく",
          "gloss": "east wind thaws the ice",
          "sekkiId": "risshun",
          "dateRange": {"start": "02-04", "end": "02-08"},
          "description": {"ja": "春の東風が氷を解かし始める。", "en": "The spring east wind begins to thaw the ice."}
        }
        """
        let data = Data(json.utf8)
        let ko = try JSONDecoder().decode(Ko.self, from: data)
        XCTAssertEqual(ko.description.ja, "春の東風が氷を解かし始める。",
                       "Japanese description must be decoded when both values present")
        XCTAssertEqual(ko.description.en, "The spring east wind begins to thaw the ice.",
                       "English description must be decoded when present")
    }
}
