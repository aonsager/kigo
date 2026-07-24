import Foundation

// MARK: - launchNotificationScheduler

/// Resolves the `NotificationScheduler` to use at app launch (Slice #220, PRD #218,
/// C23, ADR 0013/0019 resolver pattern).
///
/// Resolution rules:
/// - `KIGO_FAKE_REMINDER` present (any value) → `InMemoryNotificationScheduler`, so
///   a headless UI test can never trip the real permission prompt even if a
///   scheduling call were made.
/// - absent → `UserNotificationScheduler`, the production `UNUserNotificationCenter`
///   adapter. This is the default a **real (non-test) launch** selects.
///
/// AC5 is verified by inspecting this selection logic (asserting the returned type),
/// not by driving real notification delivery.
///
/// - Parameter environment: The launch-environment dictionary, typically
///   `ProcessInfo.processInfo.environment` at the app root.
@MainActor
public func launchNotificationScheduler(environment: [String: String]) -> any NotificationScheduler {
    #if DEBUG
    // Test-only seam: KIGO_FAKE_REMINDER swaps in the in-memory scheduler in DEBUG only (H1).
    if environment["KIGO_FAKE_REMINDER"] != nil {
        return InMemoryNotificationScheduler()
    }
    #endif
    return UserNotificationScheduler()
}
