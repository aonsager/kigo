import Foundation
import Observation

// MARK: - ReminderContent

/// The payload a scheduled daily reminder carries: today's Kigo kanji and its
/// reading, sourced through the `ContentStore` / `DateProvider` seam.
///
/// Slice #220 (PRD #218, C23, ADR 0019): the scheduling seam deals in this small,
/// UI-framework-free value rather than a `UNMutableNotificationContent`, so the
/// scheduling *decision logic* (which Kigo, at what time) is verifiable headlessly
/// against a fake scheduler with no `UNUserNotificationCenter` involvement. The
/// production adapter is the only place that maps this onto a real notification.
public struct ReminderContent: Equatable, Sendable {
    /// Kanji representation of today's Kigo (e.g. "梅雨").
    public let kanji: String
    /// Reading (yomi) of today's Kigo (e.g. "つゆ").
    public let reading: String

    public init(kanji: String, reading: String) {
        self.kanji = kanji
        self.reading = reading
    }
}

// MARK: - NotificationScheduler protocol

/// A seam for scheduling (and cancelling) the single repeating daily reminder.
///
/// Two operations only, matching the C23 scope (out of scope: a time picker, more
/// than one notification/day, push/APNs):
///  - `scheduleDaily(hour:minute:content:)` schedules **one** repeating daily local
///    notification at the given wall-clock time carrying `content`.
///  - `cancelAll()` removes every previously scheduled reminder request.
///
/// Production conforms via `UserNotificationScheduler` (a thin
/// `UNUserNotificationCenter` adapter, correct by inspection); tests inject
/// `InMemoryNotificationScheduler` and assert against its recorded state — no test
/// drives the real center or a real permission prompt (ADR 0019 / J9).
///
/// `@MainActor` matches the rest of the injected-store family (ADR 0013) and keeps
/// the coordinator's calls hop-free.
@MainActor
public protocol NotificationScheduler: AnyObject {
    /// Schedules one repeating daily notification at `hour:minute` local time.
    func scheduleDaily(hour: Int, minute: Int, content: ReminderContent) async
    /// Cancels every previously scheduled reminder request.
    func cancelAll() async
}

// MARK: - InMemoryNotificationScheduler

/// A fully in-memory `NotificationScheduler` that records what would have been
/// scheduled, for headless verification of the scheduling decision logic.
///
/// Never touches `UNUserNotificationCenter`, never prompts for permission — the
/// entire C23 scheduling contract can be exercised deterministically in
/// milliseconds by inspecting `pendingRequests`.
@Observable
@MainActor
public final class InMemoryNotificationScheduler: NotificationScheduler {

    /// One recorded scheduling call.
    public struct ScheduledRequest: Equatable, Sendable {
        public let hour: Int
        public let minute: Int
        public let content: ReminderContent

        public init(hour: Int, minute: Int, content: ReminderContent) {
            self.hour = hour
            self.minute = minute
            self.content = content
        }
    }

    /// The requests currently "pending" — appended on `scheduleDaily`, emptied on
    /// `cancelAll`. Mirrors `UNUserNotificationCenter`'s pending-request set.
    public private(set) var pendingRequests: [ScheduledRequest] = []

    public init() {}

    public func scheduleDaily(hour: Int, minute: Int, content: ReminderContent) async {
        pendingRequests.append(ScheduledRequest(hour: hour, minute: minute, content: content))
    }

    public func cancelAll() async {
        pendingRequests.removeAll()
    }
}
