@testable import KigoCore
import XCTest

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

    // MARK: - OS-derived initial language (first-launch seed) + manual-preference persistence

    /// With no persisted value, the store reports the injected `systemDefault` (the
    /// OS-derived initial language) rather than a hardcoded language.
    func testUserDefaultsStoreAbsentUsesInjectedSystemDefault() {
        let suiteName = "test.LanguagePreferenceTests.seed.\(UUID().uuidString)"
        let store = UserDefaultsLanguageStore(suiteName: suiteName, systemDefault: .english)
        XCTAssertEqual(store.preference, .english,
                       "With nothing persisted, the store must report the injected systemDefault (.english)")
        // The seed must NOT be written — the key stays absent until an explicit set(_:).
        let raw = UserDefaults(suiteName: suiteName)?.string(forKey: UserDefaultsLanguageStore.defaultsKey)
        XCTAssertNil(raw, "The OS-derived systemDefault must not be persisted; only set(_:) writes")
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    /// A preference the user has actually set persists and wins over the OS-derived
    /// systemDefault on subsequent launches (manual choice is preserved).
    func testPersistedPreferenceWinsOverSystemDefault() {
        let suiteName = "test.LanguagePreferenceTests.wins.\(UUID().uuidString)"
        // User manually picks Japanese on a device whose OS default would be English.
        let writeStore = UserDefaultsLanguageStore(suiteName: suiteName, systemDefault: .english)
        writeStore.set(.japanese)

        // A fresh launch with the same (English) OS default must still see Japanese.
        let readStore = UserDefaultsLanguageStore(suiteName: suiteName, systemDefault: .english)
        XCTAssertEqual(readStore.preference, .japanese,
                       "A manually-set preference must be preserved and win over the OS-derived systemDefault")
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    /// `initialLanguagePreference` maps the OS preferred-languages list to a supported
    /// language, falling back to English.
    func testInitialLanguagePreferenceResolvesOSLanguages() {
        XCTAssertEqual(initialLanguagePreference(preferredLanguages: ["ja-JP", "en-US"]), .japanese,
                       "Japanese at the top of the OS list must resolve to .japanese")
        XCTAssertEqual(initialLanguagePreference(preferredLanguages: ["en-US", "ja-JP"]), .english,
                       "English at the top of the OS list must resolve to .english")
        XCTAssertEqual(initialLanguagePreference(preferredLanguages: ["ja"]), .japanese,
                       "A bare 'ja' identifier must resolve to .japanese")
        XCTAssertEqual(initialLanguagePreference(preferredLanguages: ["fr-FR", "de-DE"]), .english,
                       "An unsupported OS language must fall back to .english")
        XCTAssertEqual(initialLanguagePreference(preferredLanguages: ["fr-FR", "ja-JP"]), .japanese,
                       "The first *supported* OS language wins: fr is skipped, ja matches")
        XCTAssertEqual(initialLanguagePreference(preferredLanguages: []), .english,
                       "An empty OS list must fall back to .english")
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

    // MARK: - Goal: every UI-chrome string is localised

    /// The full Japanese chrome table — every property carries the expected JA string.
    func testJapaneseChromeStringsAreComplete() {
        let s = ChromeStrings(.japanese)
        XCTAssertEqual(s.restore, "復元")
        XCTAssertEqual(s.settingsTitle, "設定")
        XCTAssertEqual(s.languageSectionLabel, "言語")
        XCTAssertEqual(s.appearanceSectionLabel, "表示")
        XCTAssertEqual(s.subscriptionSectionLabel, "購読")
        XCTAssertEqual(s.appearanceSystem, "システム")
        XCTAssertEqual(s.appearanceLight, "ライト")
        XCTAssertEqual(s.appearanceDark, "ダーク")
        XCTAssertEqual(s.subscriptionActive, "購読中")
        XCTAssertEqual(s.subscribe, "購読する")
        XCTAssertEqual(s.understandingLabel, "意味")
        XCTAssertEqual(s.termsOfUse, "利用規約")
        XCTAssertEqual(s.privacyPolicy, "プライバシーポリシー")
        XCTAssertEqual(s.upsellTitle, "意味をひらく")
        XCTAssertEqual(s.loading, "読み込み中…")
        XCTAssertEqual(s.contentUnavailable, "コンテンツは現在利用できません")
        XCTAssertEqual(s.seasonSpring, "春")
        XCTAssertEqual(s.seasonSummer, "夏")
        XCTAssertEqual(s.seasonAutumn, "秋")
        XCTAssertEqual(s.seasonWinter, "冬")
        XCTAssertEqual(s.almanacKoHeader, "候")
        XCTAssertEqual(s.almanacSekkiHeader, "節気")
    }

    /// The full English chrome table — every property carries the expected EN string.
    func testEnglishChromeStringsAreComplete() {
        let s = ChromeStrings(.english)
        XCTAssertEqual(s.restore, "Restore Purchases")
        XCTAssertEqual(s.settingsTitle, "Settings")
        XCTAssertEqual(s.languageSectionLabel, "Language")
        XCTAssertEqual(s.appearanceSectionLabel, "Appearance")
        XCTAssertEqual(s.subscriptionSectionLabel, "Subscription")
        XCTAssertEqual(s.appearanceSystem, "System")
        XCTAssertEqual(s.appearanceLight, "Light")
        XCTAssertEqual(s.appearanceDark, "Dark")
        XCTAssertEqual(s.subscriptionActive, "Subscription active")
        XCTAssertEqual(s.subscribe, "Subscribe")
        XCTAssertEqual(s.understandingLabel, "Understanding")
        XCTAssertEqual(s.termsOfUse, "Terms of Use")
        XCTAssertEqual(s.privacyPolicy, "Privacy Policy")
        XCTAssertEqual(s.upsellTitle, "Open the meaning")
        XCTAssertEqual(s.loading, "Loading…")
        XCTAssertEqual(s.contentUnavailable, "Content is currently unavailable")
        XCTAssertEqual(s.seasonSpring, "Spring")
        XCTAssertEqual(s.seasonSummer, "Summer")
        XCTAssertEqual(s.seasonAutumn, "Autumn")
        XCTAssertEqual(s.seasonWinter, "Winter")
        XCTAssertEqual(s.almanacKoHeader, "Microseason")
        XCTAssertEqual(s.almanacSekkiHeader, "Solar term")
    }

    /// Every localisable chrome property must actually differ between JA and EN — a guard
    /// against accidentally hardcoding one language into both branches.
    func testChromeStringsDifferAcrossLanguages() {
        let ja = ChromeStrings(.japanese)
        let en = ChromeStrings(.english)
        let pairs: [(String, String, String)] = [
            ("restore", ja.restore, en.restore),
            ("settingsTitle", ja.settingsTitle, en.settingsTitle),
            ("languageSectionLabel", ja.languageSectionLabel, en.languageSectionLabel),
            ("appearanceSectionLabel", ja.appearanceSectionLabel, en.appearanceSectionLabel),
            ("subscriptionSectionLabel", ja.subscriptionSectionLabel, en.subscriptionSectionLabel),
            ("appearanceSystem", ja.appearanceSystem, en.appearanceSystem),
            ("appearanceLight", ja.appearanceLight, en.appearanceLight),
            ("appearanceDark", ja.appearanceDark, en.appearanceDark),
            ("subscriptionActive", ja.subscriptionActive, en.subscriptionActive),
            ("subscribe", ja.subscribe, en.subscribe),
            ("understandingLabel", ja.understandingLabel, en.understandingLabel),
            ("understandingBenefit", ja.understandingBenefit, en.understandingBenefit),
            ("understandingSettingsNote", ja.understandingSettingsNote, en.understandingSettingsNote),
            ("meaningPreviewSubscribe", ja.meaningPreviewSubscribe, en.meaningPreviewSubscribe),
            ("termsOfUse", ja.termsOfUse, en.termsOfUse),
            ("privacyPolicy", ja.privacyPolicy, en.privacyPolicy),
            ("upsellTitle", ja.upsellTitle, en.upsellTitle),
            ("upsellBody", ja.upsellBody, en.upsellBody),
            ("loading", ja.loading, en.loading),
            ("contentUnavailable", ja.contentUnavailable, en.contentUnavailable),
            ("seasonSpring", ja.seasonSpring, en.seasonSpring),
            ("seasonSummer", ja.seasonSummer, en.seasonSummer),
            ("seasonAutumn", ja.seasonAutumn, en.seasonAutumn),
            ("seasonWinter", ja.seasonWinter, en.seasonWinter),
            ("almanacKoHeader", ja.almanacKoHeader, en.almanacKoHeader),
            ("almanacSekkiHeader", ja.almanacSekkiHeader, en.almanacSekkiHeader),
            ("a11yLoading", ja.a11yLoading, en.a11yLoading),
            ("a11yContentUnavailable", ja.a11yContentUnavailable, en.a11yContentUnavailable),
            ("a11yUnlockMeaning", ja.a11yUnlockMeaning, en.a11yUnlockMeaning),
            ("a11yDismiss", ja.a11yDismiss, en.a11yDismiss),
            ("a11yBackgroundImage", ja.a11yBackgroundImage, en.a11yBackgroundImage),
        ]
        for (name, j, e) in pairs {
            XCTAssertNotEqual(j, e, "\(name) must be localised — JA and EN must differ (got '\(j)' for both)")
            XCTAssertFalse(j.isEmpty, "\(name) JA must be non-empty")
            XCTAssertFalse(e.isEmpty, "\(name) EN must be non-empty")
        }
    }

    /// Interpolated accessibility labels must localise and embed the passed numbers.
    func testInterpolatedAccessibilityLabelsLocalise() {
        let ja = ChromeStrings(.japanese)
        let en = ChromeStrings(.english)
        XCTAssertEqual(en.a11yMicroseasonTimeline(ko: 3, of: 72), "Microseason timeline: Kō 3 of 72")
        XCTAssertNotEqual(ja.a11yMicroseasonTimeline(ko: 3, of: 72), en.a11yMicroseasonTimeline(ko: 3, of: 72))
        XCTAssertEqual(en.a11yDayInMicroseason(day: 2, of: 5), "Day 2 of 5 in this microseason")
        XCTAssertNotEqual(ja.a11yDayInMicroseason(day: 2, of: 5), en.a11yDayInMicroseason(day: 2, of: 5))
        XCTAssertEqual(en.a11yKoInSolarTerm(ko: 1, of: 3), "Kō 1 of 3 in this solar term")
        XCTAssertNotEqual(ja.a11yKoInSolarTerm(ko: 1, of: 3), en.a11yKoInSolarTerm(ko: 1, of: 3))
    }

    // MARK: - Exception: the language picker options are self-named, not localised

    /// The language-picker option labels use each language's own endonym and are
    /// constant regardless of the active UI language (the single carve-out from the
    /// localisation rule).
    func testLanguageSelfNamesAreEndonymsAndConstant() {
        XCTAssertEqual(LanguagePreference.japanese.selfName, "日本語")
        XCTAssertEqual(LanguagePreference.english.selfName, "English")
        // "Constant regardless of active language": selfName is a property of the
        // option itself, so switching the active preference cannot change either label.
        XCTAssertEqual(LanguagePreference.japanese.selfName, "日本語",
                       "The Japanese option must always read 日本語, never a localised 'Japanese'")
    }
}
