import XCTest
@testable import Kigo

// MARK: - LaunchNotificationSchedulerTests
//
// Slice #220 (PRD #218, C23, ADR 0019): verifies the launch resolvers'
// *selection logic* by inspecting the returned type — never by driving real
// notification delivery or a real permission prompt (AC5).
@MainActor
final class LaunchNotificationSchedulerTests: XCTestCase {

    // MARK: - AC5: default resolver selects the production scheduler

    /// With no `KIGO_FAKE_REMINDER`, the resolver must select the production
    /// `UNUserNotificationCenter`-backed scheduler — the path a real launch takes.
    func testDefaultResolverSelectsProductionScheduler() {
        let scheduler = launchNotificationScheduler(environment: [:])
        XCTAssertTrue(
            scheduler is UserNotificationScheduler,
            "Absent KIGO_FAKE_REMINDER, the resolver must select the production UserNotificationScheduler"
        )
    }

    /// Under the `KIGO_FAKE_REMINDER` fake path the resolver must select the
    /// in-memory scheduler, so a headless UI test can never trip a real prompt.
    func testFakeReminderEnvSelectsInMemoryScheduler() {
        let scheduler = launchNotificationScheduler(environment: ["KIGO_FAKE_REMINDER": "on"])
        XCTAssertTrue(
            scheduler is InMemoryNotificationScheduler,
            "KIGO_FAKE_REMINDER present must select the in-memory (fake) scheduler"
        )
    }

    // MARK: - launchReminderStore selection

    /// `KIGO_FAKE_REMINDER=on` seeds a locked in-memory store reading enabled.
    func testLaunchReminderStoreOnSeedsEnabledLockedStore() {
        let store = launchReminderStore(environment: ["KIGO_FAKE_REMINDER": "on"])
        XCTAssertTrue(store is LockedInMemoryReminderStore, "on → locked in-memory store")
        XCTAssertTrue(store.isEnabled, "KIGO_FAKE_REMINDER=on must seed the store enabled")

        // Locked: navigating settings (a set call) must not change it.
        store.set(false)
        XCTAssertTrue(store.isEnabled, "A locked seeded store must ignore set(_:)")
    }

    /// `KIGO_FAKE_REMINDER=off` seeds a locked in-memory store reading disabled.
    func testLaunchReminderStoreOffSeedsDisabledLockedStore() {
        let store = launchReminderStore(environment: ["KIGO_FAKE_REMINDER": "off"])
        XCTAssertTrue(store is LockedInMemoryReminderStore, "off → locked in-memory store")
        XCTAssertFalse(store.isEnabled, "KIGO_FAKE_REMINDER=off must seed the store disabled")
    }

    /// Absent env → the persisted production store (default-off preserved).
    func testLaunchReminderStoreDefaultSelectsUserDefaultsStore() {
        let store = launchReminderStore(environment: [:])
        XCTAssertTrue(
            store is UserDefaultsReminderStore,
            "Absent KIGO_FAKE_REMINDER, the resolver must select the persisted UserDefaultsReminderStore"
        )
    }
}
