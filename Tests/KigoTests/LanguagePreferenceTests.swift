import XCTest
@testable import Kigo

/// Tests for `LanguagePreference`, `ChromeStrings`, and `InMemoryLanguageStore`.
///
/// All tests are purely in-memory — no app launch, no StoreKit, no network.
/// The store is injectable (`InMemoryLanguageStore`) so the test exercises the
/// complete reading/writing cycle headlessly (mirrors `PaywallTests` / ADR 0009).
///
/// Acceptance criteria (Slice #136):
///  AC1: Default store → Japanese chrome
///  AC2: After setting `.english` → English chrome
///  AC3: Store initialised with unknown/absent value → `.japanese` fallback
@MainActor
final class LanguagePreferenceTests: XCTestCase {

    // MARK: - AC1: Default preference is Japanese

    /// `InMemoryLanguageStore()` with no arguments must default to `.japanese`.
    func testDefaultPreferenceIsJapanese() {
        let store = InMemoryLanguageStore()
        XCTAssertEqual(store.preference, .japanese,
                       "A freshly created InMemoryLanguageStore must default to .japanese")
    }

    /// `ChromeStrings` built from the default store must return the Japanese restore string.
    func testDefaultChromeStringsRestoreIsJapanese() {
        let store = InMemoryLanguageStore()
        let strings = ChromeStrings(store.preference)
        XCTAssertEqual(strings.restore, ChromeStrings.japaneseRestore,
                       "ChromeStrings(InMemoryLanguageStore().preference).restore must equal the Japanese restore string")
    }

    // MARK: - AC2: Setting .english returns English chrome

    /// After calling `store.set(.english)`, `ChromeStrings` must return the English restore string.
    func testSettingEnglishPreferenceReturnsEnglishRestore() {
        let store = InMemoryLanguageStore()
        store.set(.english)
        let strings = ChromeStrings(store.preference)
        XCTAssertEqual(strings.restore, ChromeStrings.englishRestore,
                       "After setting .english, ChromeStrings.restore must equal the English restore string")
    }

    // MARK: - AC3: Unknown/absent value falls back to .japanese

    /// `InMemoryLanguageStore(rawValue: nil)` must fall back to `.japanese`.
    func testAbsentRawValueFallsBackToJapanese() {
        let store = InMemoryLanguageStore(rawValue: nil)
        XCTAssertEqual(store.preference, .japanese,
                       "InMemoryLanguageStore(rawValue: nil) must default to .japanese")
    }

    /// `InMemoryLanguageStore(rawValue: "unknown")` must fall back to `.japanese`.
    func testUnknownRawValueFallsBackToJapanese() {
        let store = InMemoryLanguageStore(rawValue: "unknown_language_code")
        XCTAssertEqual(store.preference, .japanese,
                       "InMemoryLanguageStore(rawValue: unknown) must fall back to .japanese")
    }

    // MARK: - Round-trip: set then read

    /// Setting `.japanese` explicitly, then reading back via ChromeStrings, returns Japanese chrome.
    func testRoundTripJapaneseChromeAfterExplicitSet() {
        let store = InMemoryLanguageStore()
        store.set(.english)
        store.set(.japanese)
        let strings = ChromeStrings(store.preference)
        XCTAssertEqual(strings.restore, ChromeStrings.japaneseRestore,
                       "After setting back to .japanese, ChromeStrings.restore must be the Japanese string")
    }
}
