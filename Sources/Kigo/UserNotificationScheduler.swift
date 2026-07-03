import Foundation
import UserNotifications

// MARK: - UserNotificationScheduler

/// The production `NotificationScheduler`: a thin, correct-by-inspection adapter
/// over `UNUserNotificationCenter` (Slice #220, PRD #218, C23, ADR 0019).
///
/// - `scheduleDaily` requests notification authorization, then adds a single
///   `UNNotificationRequest` under a fixed identifier with a
///   `UNCalendarNotificationTrigger(dateMatching:repeats:true)` firing daily at
///   the given wall-clock time. The fixed identifier means a re-schedule replaces
///   rather than stacks (the coordinator additionally `cancelAll`s first).
/// - `cancelAll` calls `removeAllPendingNotificationRequests()`.
///
/// This type is deliberately never exercised on the loop's gating path: the real
/// permission prompt / delivery hang headlessly under `xcodebuild test` (ADR 0019 /
/// J9, the same shape as the StoreKit trap). All scheduling *logic* is verified via
/// `InMemoryNotificationScheduler`; this adapter is correct by inspection.
///
/// `UNUserNotificationCenter.current()` is resolved lazily (a computed property)
/// rather than stored at init, so constructing the scheduler — e.g. when
/// `launchNotificationScheduler` selects it as the default — never touches the
/// center. That keeps the resolver-selection unit test (AC5) from requiring a
/// notification-capable host.
@MainActor
public final class UserNotificationScheduler: NotificationScheduler {

    /// The single request identifier used for the daily reminder, so scheduling is
    /// idempotent (a new request under the same id replaces the old one).
    public static let requestIdentifier = "kigo.dailyReminder"

    private var center: UNUserNotificationCenter { .current() }

    public init() {}

    public func scheduleDaily(hour: Int, minute: Int, content: ReminderContent) async {
        // Ask for permission; if the user declines there is simply nothing to
        // deliver. We do not gate on the result — adding the request is harmless
        // and the OS drops it when unauthorized.
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])

        let notification = UNMutableNotificationContent()
        notification.title = content.kanji
        notification.body = content.reading
        notification.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let request = UNNotificationRequest(
            identifier: Self.requestIdentifier,
            content: notification,
            trigger: trigger
        )
        try? await center.add(request)
    }

    public func cancelAll() async {
        center.removeAllPendingNotificationRequests()
    }
}
