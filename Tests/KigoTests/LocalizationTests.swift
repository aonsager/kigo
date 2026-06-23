import XCTest
import SwiftUI
@testable import Kigo

// MARK: - LocalizationTests
//
// Slice #174: LocalizedText.localized(for:) + LanguagePreferenceKey unit tests.
//
// Acceptance criteria verified:
//   AC-localized-english: LocalizedText(ja:en:).localized(for: .english) returns "en" value.
//   AC-localized-japanese: LocalizedText(ja:en:).localized(for: .japanese) returns "ja" value.
//   AC-localized-fallback: LocalizedText(ja:, en: nil).localized(for: .english) returns "ja".
//   AC-env-key-default: @Environment(\.language) resolves to .japanese without injection.

@MainActor
final class LocalizationTests: XCTestCase {

    // MARK: - LocalizedText.localized(for:)

    /// `.localized(for: .english)` must return the `en` value when present.
    func testLocalizedForEnglishReturnsEnglishValue() {
        let text = LocalizedText(ja: "うめ", en: "ume")
        XCTAssertEqual(
            text.localized(for: .english), "ume",
            "localized(for: .english) must return the en value when present"
        )
    }

    /// `.localized(for: .japanese)` must return the `ja` value.
    func testLocalizedForJapaneseReturnsJapaneseValue() {
        let text = LocalizedText(ja: "うめ", en: "ume")
        XCTAssertEqual(
            text.localized(for: .japanese), "うめ",
            "localized(for: .japanese) must return the ja value"
        )
    }

    /// `.localized(for: .english)` on a nil-en field must fall back to `ja`.
    func testLocalizedForEnglishFallsBackToJapaneseWhenEnIsNil() {
        let text = LocalizedText(ja: "うめ", en: nil)
        XCTAssertEqual(
            text.localized(for: .english), "うめ",
            "localized(for: .english) must return ja when en is nil"
        )
    }

    /// `.localized(for: .japanese)` on a nil-en field returns `ja` (no change).
    func testLocalizedForJapaneseWithNilEnReturnsJapanese() {
        let text = LocalizedText(ja: "うめ", en: nil)
        XCTAssertEqual(
            text.localized(for: .japanese), "うめ",
            "localized(for: .japanese) must return ja even when en is nil"
        )
    }

    // MARK: - LanguagePreferenceKey / EnvironmentValues.language

    /// `EnvironmentValues.language` must default to `.japanese` without explicit injection.
    func testEnvironmentLanguageKeyDefaultsToJapanese() {
        // Access the default value directly via EnvironmentValues.
        let env = EnvironmentValues()
        XCTAssertEqual(
            env.language, .japanese,
            "@Environment(\\.language) must resolve to .japanese when no explicit injection is present"
        )
    }
}
