import XCTest
import SwiftUI
@testable import Kigo

/// Tests for `AppearancePreference`, `InMemoryAppearanceStore`,
/// `UserDefaultsAppearanceStore`, and `launchAppearanceStore` (Slice D / issue #161).
///
/// All tests are purely in-memory — no app launch, no StoreKit, no network.
/// The store is injectable so the test exercises the complete reading/writing
/// cycle headlessly (mirrors `LanguagePreferenceTests` / `LaunchColorSchemeTests`).
///
/// Acceptance criteria:
///  AC1: Default store → `.system`
///  AC2: `colorScheme` mapping (system→nil, light→.light, dark→.dark)
///  AC3: In-memory `set` updates the preference
///  AC4: `UserDefaultsAppearanceStore` write → re-read round-trip on the same suite
///  AC5: `UserDefaultsAppearanceStore` returns `.system` when key absent or garbage
///  AC6: `launchAppearanceStore` with `KIGO_FAKE_APPEARANCE=dark` returns locked `.dark`
///  AC7: `launchAppearanceStore` with `KIGO_FAKE_APPEARANCE=light` returns locked `.light`
///  AC8: `launchAppearanceStore` absent → returns a `UserDefaultsAppearanceStore` defaulting to `.system`
@MainActor
final class AppearancePreferenceTests: XCTestCase {

    // MARK: - AC1: Default preference is .system

    /// A freshly created `InMemoryAppearanceStore` must default to `.system`.
    func testDefaultPreferenceIsSystem() {
        let store = InMemoryAppearanceStore()
        XCTAssertEqual(store.preference, .system,
                       "A freshly created InMemoryAppearanceStore must default to .system")
    }

    /// `InMemoryAppearanceStore(rawValue: nil)` must fall back to `.system`.
    func testAbsentRawValueFallsBackToSystem() {
        let store = InMemoryAppearanceStore(rawValue: nil)
        XCTAssertEqual(store.preference, .system,
                       "InMemoryAppearanceStore(rawValue: nil) must default to .system")
    }

    /// `InMemoryAppearanceStore(rawValue: "unknown")` must fall back to `.system`.
    func testUnknownRawValueFallsBackToSystem() {
        let store = InMemoryAppearanceStore(rawValue: "not_a_valid_appearance")
        XCTAssertEqual(store.preference, .system,
                       "InMemoryAppearanceStore(rawValue: unknown) must fall back to .system")
    }

    // MARK: - AC2: colorScheme mapping

    /// `.system` must map to `nil` (let the system decide).
    func testSystemMapsToNilColorScheme() {
        XCTAssertNil(AppearancePreference.system.colorScheme,
                     ".system must map to a nil ColorScheme")
    }

    /// `.light` must map to `ColorScheme.light`.
    func testLightMapsToLightColorScheme() {
        XCTAssertEqual(AppearancePreference.light.colorScheme, .light,
                       ".light must map to ColorScheme.light")
    }

    /// `.dark` must map to `ColorScheme.dark`.
    func testDarkMapsToDarkColorScheme() {
        XCTAssertEqual(AppearancePreference.dark.colorScheme, .dark,
                       ".dark must map to ColorScheme.dark")
    }

    // MARK: - AC3: In-memory set updates the preference

    /// After `store.set(.dark)`, the preference must read back `.dark`.
    func testSettingDarkUpdatesPreference() {
        let store = InMemoryAppearanceStore()
        store.set(.dark)
        XCTAssertEqual(store.preference, .dark,
                       "After set(.dark), the preference must be .dark")
    }

    /// After `store.set(.light)`, the preference must read back `.light`.
    func testSettingLightUpdatesPreference() {
        let store = InMemoryAppearanceStore()
        store.set(.light)
        XCTAssertEqual(store.preference, .light,
                       "After set(.light), the preference must be .light")
    }

    // MARK: - AC4: UserDefaultsAppearanceStore write → re-read round-trip

    /// Writing `.dark` to a `UserDefaultsAppearanceStore` and re-reading via a fresh
    /// instance pointed at the same suite must return `.dark`.
    func testUserDefaultsStoreRoundTrip() {
        let suiteName = "test.AppearancePreferenceTests.roundtrip.\(UUID().uuidString)"
        let writeStore = UserDefaultsAppearanceStore(suiteName: suiteName)
        writeStore.set(.dark)

        let readStore = UserDefaultsAppearanceStore(suiteName: suiteName)
        XCTAssertEqual(readStore.preference, .dark,
                       "Re-reading via a fresh UserDefaultsAppearanceStore over the same suite must return .dark")

        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    // MARK: - AC5: UserDefaultsAppearanceStore absent/garbage → .system

    /// When the key is absent (empty suite) the store must return `.system`.
    func testUserDefaultsStoreAbsentKeyFallsBackToSystem() {
        let suiteName = "test.AppearancePreferenceTests.absent.\(UUID().uuidString)"
        let store = UserDefaultsAppearanceStore(suiteName: suiteName)
        XCTAssertEqual(store.preference, .system,
                       "UserDefaultsAppearanceStore must return .system when the key is absent")

        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    /// When the defaults key holds a garbage value the store must return `.system`.
    func testUserDefaultsStoreGarbageKeyFallsBackToSystem() {
        let suiteName = "test.AppearancePreferenceTests.garbage.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set("not_a_valid_appearance", forKey: UserDefaultsAppearanceStore.defaultsKey)

        let store = UserDefaultsAppearanceStore(suiteName: suiteName)
        XCTAssertEqual(store.preference, .system,
                       "UserDefaultsAppearanceStore must return .system when the key holds a garbage value")

        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - AC6 / AC7: launchAppearanceStore env-var branches

    /// `KIGO_FAKE_APPEARANCE=dark` must return a store locked to `.dark` that ignores `set(_:)`.
    func testLaunchAppearanceStoreDarkReturnsLockedDark() {
        let store = launchAppearanceStore(environment: ["KIGO_FAKE_APPEARANCE": "dark"])
        XCTAssertEqual(store.preference, .dark,
                       "KIGO_FAKE_APPEARANCE=dark must produce a store whose preference is .dark")
        store.set(.light)
        XCTAssertEqual(store.preference, .dark,
                       "A locked store must ignore set(_:) calls")
    }

    /// `KIGO_FAKE_APPEARANCE=light` must return a store locked to `.light` that ignores `set(_:)`.
    func testLaunchAppearanceStoreLightReturnsLockedLight() {
        let store = launchAppearanceStore(environment: ["KIGO_FAKE_APPEARANCE": "light"])
        XCTAssertEqual(store.preference, .light,
                       "KIGO_FAKE_APPEARANCE=light must produce a store whose preference is .light")
        store.set(.dark)
        XCTAssertEqual(store.preference, .light,
                       "A locked store must ignore set(_:) calls")
    }

    // MARK: - AC8: launchAppearanceStore absent → UserDefaultsAppearanceStore (.system)

    /// When `KIGO_FAKE_APPEARANCE` is absent, `launchAppearanceStore` must return a
    /// `UserDefaultsAppearanceStore` defaulting to `.system`.
    func testLaunchAppearanceStoreAbsentReturnsUserDefaultsStore() {
        let store = launchAppearanceStore(environment: [:])
        XCTAssertTrue(store is UserDefaultsAppearanceStore,
                      "launchAppearanceStore with no KIGO_FAKE_APPEARANCE must return a UserDefaultsAppearanceStore")
        XCTAssertEqual(store.preference, .system,
                       "launchAppearanceStore with no override must default to .system")
    }

    /// An unrecognised `KIGO_FAKE_APPEARANCE` value must also fall back to `UserDefaultsAppearanceStore`.
    func testLaunchAppearanceStoreUnrecognisedValueFallsBack() {
        let store = launchAppearanceStore(environment: ["KIGO_FAKE_APPEARANCE": "auto"])
        XCTAssertTrue(store is UserDefaultsAppearanceStore,
                      "launchAppearanceStore with unrecognised KIGO_FAKE_APPEARANCE must return UserDefaultsAppearanceStore")
    }
}
