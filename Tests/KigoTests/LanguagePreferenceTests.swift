import XCTest
@testable import Kigo

/// Tests for `LanguagePreference`, `ChromeStrings`, `InMemoryLanguageStore`,
/// `UserDefaultsLanguageStore`, and `launchLanguageStore`.
///
/// All tests are purely in-memory — no app launch, no StoreKit, no network.
/// The store is injectable so the test exercises the complete reading/writing
/// cycle headlessly (mirrors `PaywallTests` / ADR 0009).
///
/// Acceptance criteria (Slice #136):
///  AC1: Default store → Japanese chrome
///  AC2: After setting `.english` → English chrome
///  AC3: Store initialised with unknown/absent value → `.japanese` fallback
///
/// Acceptance criteria (Slice #137):
///  AC4: `UserDefaultsLanguageStore` write → re-read round-trip returns `.english`
///  AC5: `UserDefaultsLanguageStore` returns `.japanese` when key absent or garbage
///  AC6: `launchLanguageStore(environment:)` with `KIGO_FAKE_LANGUAGE=en` returns locked `.english` store
///  AC7: `launchLanguageStore(environment:)` with `KIGO_FAKE_LANGUAGE=ja` returns locked `.japanese` store
///  AC8: `launchLanguageStore(environment:)` absent → returns `UserDefaultsLanguageStore`
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

    // MARK: - AC4: UserDefaultsLanguageStore write → re-read round-trip

    /// Writing `.english` to a `UserDefaultsLanguageStore` and re-reading via a fresh
    /// instance pointed at the same suite must return `.english`.
    func testUserDefaultsStoreRoundTrip() {
        let suiteName = "test.LanguagePreferenceTests.roundtrip.\(UUID().uuidString)"
        let writeStore = UserDefaultsLanguageStore(suiteName: suiteName)
        writeStore.set(.english)

        // A fresh instance over the same suite must see the written value.
        let readStore = UserDefaultsLanguageStore(suiteName: suiteName)
        XCTAssertEqual(readStore.preference, .english,
                       "Re-reading via a fresh UserDefaultsLanguageStore over the same suite must return .english")

        // Cleanup — remove the test suite from UserDefaults.
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    // MARK: - AC5: UserDefaultsLanguageStore absent/garbage → .japanese

    /// When the key is absent (empty suite) the store must return `.japanese`.
    func testUserDefaultsStoreAbsentKeyFallsBackToJapanese() {
        let suiteName = "test.LanguagePreferenceTests.absent.\(UUID().uuidString)"
        let store = UserDefaultsLanguageStore(suiteName: suiteName)
        XCTAssertEqual(store.preference, .japanese,
                       "UserDefaultsLanguageStore must return .japanese when the key is absent")

        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    /// When the defaults key holds a garbage value (unrecognised raw string) the store
    /// must return `.japanese`.
    func testUserDefaultsStoreGarbageKeyFallsBackToJapanese() {
        let suiteName = "test.LanguagePreferenceTests.garbage.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set("not_a_valid_language", forKey: UserDefaultsLanguageStore.defaultsKey)

        let store = UserDefaultsLanguageStore(suiteName: suiteName)
        XCTAssertEqual(store.preference, .japanese,
                       "UserDefaultsLanguageStore must return .japanese when the key holds a garbage value")

        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - AC6 / AC7: launchLanguageStore env-var branches

    /// `KIGO_FAKE_LANGUAGE=en` must return a store locked to `.english` that ignores `set(_:)`.
    func testLaunchLanguageStoreEnglishReturnsLockedEnglish() {
        let store = launchLanguageStore(environment: ["KIGO_FAKE_LANGUAGE": "en"])
        XCTAssertEqual(store.preference, .english,
                       "KIGO_FAKE_LANGUAGE=en must produce a store whose preference is .english")
        // The store is locked; calling set should not change the preference.
        store.set(.japanese)
        XCTAssertEqual(store.preference, .english,
                       "A locked store must ignore set(_:) calls")
    }

    /// `KIGO_FAKE_LANGUAGE=ja` must return a store locked to `.japanese` that ignores `set(_:)`.
    func testLaunchLanguageStoreJapaneseReturnsLockedJapanese() {
        let store = launchLanguageStore(environment: ["KIGO_FAKE_LANGUAGE": "ja"])
        XCTAssertEqual(store.preference, .japanese,
                       "KIGO_FAKE_LANGUAGE=ja must produce a store whose preference is .japanese")
        store.set(.english)
        XCTAssertEqual(store.preference, .japanese,
                       "A locked store must ignore set(_:) calls")
    }

    // MARK: - AC8: launchLanguageStore absent → UserDefaultsLanguageStore

    /// When `KIGO_FAKE_LANGUAGE` is absent, `launchLanguageStore` must return a
    /// `UserDefaultsLanguageStore` (not an `InMemoryLanguageStore`).
    func testLaunchLanguageStoreAbsentReturnsUserDefaultsStore() {
        let store = launchLanguageStore(environment: [:])
        XCTAssertTrue(store is UserDefaultsLanguageStore,
                      "launchLanguageStore with no KIGO_FAKE_LANGUAGE must return a UserDefaultsLanguageStore")
    }

    /// An unrecognised `KIGO_FAKE_LANGUAGE` value must also fall back to `UserDefaultsLanguageStore`.
    func testLaunchLanguageStoreUnrecognisedValueFallsBack() {
        let store = launchLanguageStore(environment: ["KIGO_FAKE_LANGUAGE": "fr"])
        XCTAssertTrue(store is UserDefaultsLanguageStore,
                      "launchLanguageStore with unrecognised KIGO_FAKE_LANGUAGE must return UserDefaultsLanguageStore")
    }
}
