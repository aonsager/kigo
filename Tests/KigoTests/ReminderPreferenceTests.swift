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
}
