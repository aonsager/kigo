import Foundation

// MARK: - ReminderNotificationCoordinator

/// Turns the daily-reminder *preference* into concrete scheduling calls against a
/// `NotificationScheduler`, pulling today's Kigo through the `ContentStore` /
/// `DateProvider` seam (Slice #220, PRD #218, C23, ADR 0019).
///
/// This is the single place the C23 scheduling decision lives, so it can be
/// verified headlessly with an injected fake scheduler and a `ContentStore` over a
/// `FixedDateProvider` — no `UNUserNotificationCenter`, no permission prompt.
///
/// Decision rules (`apply(isEnabled:)`):
///  - **enabled**: cancel any existing reminder, then schedule exactly one
///    repeating daily notification at 08:00 local time carrying today's Kigo kanji
///    and reading. If today's content cannot be resolved yet, nothing is scheduled.
///  - **disabled**: cancel every previously scheduled reminder request.
///
/// The `cancelAll` before scheduling guarantees "exactly one" even if `apply(true)`
/// is called repeatedly (e.g. re-enabling), mirroring the fixed-identifier
/// idempotency of the production adapter.
@MainActor
public final class ReminderNotificationCoordinator {

    /// The wall-clock time the daily reminder fires (08:00 local). C23 fixes this;
    /// a user-configurable time picker is explicitly out of scope.
    public static let reminderHour = 8
    public static let reminderMinute = 0

    private let scheduler: any NotificationScheduler
    private let contentStore: ContentStore

    public init(scheduler: any NotificationScheduler, contentStore: ContentStore) {
        self.scheduler = scheduler
        self.contentStore = contentStore
    }

    /// Reconciles the scheduler with the given preference value.
    public func apply(isEnabled: Bool) async {
        guard isEnabled else {
            await scheduler.cancelAll()
            return
        }

        // Clear any prior reminder so enabling always yields exactly one request.
        await scheduler.cancelAll()

        // Pull today's Kigo through the ContentStore/DateProvider seam. If content
        // has not resolved yet there is nothing to carry, so schedule nothing.
        guard let resolved = contentStore.todayResolved() else { return }

        let content = ReminderContent(
            kanji: resolved.kigoEntry.kanji,
            reading: resolved.kigoEntry.reading.ja
        )
        await scheduler.scheduleDaily(
            hour: Self.reminderHour,
            minute: Self.reminderMinute,
            content: content
        )
    }
}
