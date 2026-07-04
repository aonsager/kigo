import XCTest
@testable import Kigo

/// Tests for `ReminderStore`, `InMemoryReminderStore`, and `UserDefaultsReminderStore`
/// (Slice #219 — the first of two slices for PRD #218 / C23, ADR 0019).
///
/// All tests are purely in-memory — no app launch, no notification permission
/// prompt, no `UNUserNotificationCenter`. This slice is persistence + UI only;
/// the scheduling seam (`NotificationScheduler`) is slice #220.
///
/// Acceptance criteria:
///  AC1: A freshly created `InMemoryReminderStore` defaults to disabled.
///  AC2: In-memory `set(true)` / `set(false)` updates `isEnabled`.
///  AC3: `UserDefaultsReminderStore` write → re-read round-trip on the same suite.
///  AC4: `UserDefaultsReminderStore` defaults to disabled when the key is absent (unset store).
@MainActor
final class ReminderPreferenceTests: XCTestCase {

    // MARK: - AC1: Default preference is disabled

    /// A freshly created `InMemoryReminderStore` must default to disabled.
    func testDefaultPreferenceIsDisabled() {
        let store = InMemoryReminderStore()
        XCTAssertFalse(store.isEnabled,
                        "A freshly created InMemoryReminderStore must default to disabled")
    }

    // MARK: - AC2: In-memory set updates the preference

    /// After `store.set(true)`, `isEnabled` must read back `true`.
    func testSettingEnabledUpdatesPreference() {
        let store = InMemoryReminderStore()
        store.set(true)
        XCTAssertTrue(store.isEnabled,
                      "After set(true), isEnabled must be true")
    }

    /// After enabling then disabling, `isEnabled` must read back `false`.
    func testSettingDisabledUpdatesPreference() {
        let store = InMemoryReminderStore(isEnabled: true)
        store.set(false)
        XCTAssertFalse(store.isEnabled,
                        "After set(false), isEnabled must be false")
    }

    // MARK: - AC3: UserDefaultsReminderStore write → re-read round-trip

    /// Writing `true` to a `UserDefaultsReminderStore` and re-reading via a fresh
    /// instance pointed at the same suite must return `true`.
    func testUserDefaultsStoreRoundTrip() {
        let suiteName = "test.ReminderPreferenceTests.roundtrip.\(UUID().uuidString)"
        let writeStore = UserDefaultsReminderStore(suiteName: suiteName)
        writeStore.set(true)

        let readStore = UserDefaultsReminderStore(suiteName: suiteName)
        XCTAssertTrue(readStore.isEnabled,
                      "Re-reading via a fresh UserDefaultsReminderStore over the same suite must return true")

        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    // MARK: - AC4: UserDefaultsReminderStore unset → disabled

    /// When the key is absent (a fresh install / unset store) the store must default to disabled.
    func testUserDefaultsStoreUnsetDefaultsToDisabled() {
        let suiteName = "test.ReminderPreferenceTests.absent.\(UUID().uuidString)"
        let store = UserDefaultsReminderStore(suiteName: suiteName)
        XCTAssertFalse(store.isEnabled,
                        "UserDefaultsReminderStore must default to disabled when unset")

        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }
}
