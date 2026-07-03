import Observation

// MARK: - ReminderStore protocol

/// A read/write store for the user's daily-reminder preference.
///
/// Mirrors `LanguageStore` / `AppearanceStore` (ADR 0013's injected-store
/// pattern): conformers are `@Observable @MainActor` classes so SwiftUI can
/// track mutations reactively. Both requirements are `@MainActor`.
///
/// Slice #219 (PRD #218, C23, ADR 0019): this store carries only the
/// persisted **preference** — on/off — for the `settings.dailyReminder`
/// toggle. It has no knowledge of `UNUserNotificationCenter`, permission
/// prompts, or scheduling; the `NotificationScheduler` seam that turns this
/// preference into an actual scheduled notification is slice #220.
@MainActor
public protocol ReminderStore: AnyObject {
    var isEnabled: Bool { get }
    func set(_ isEnabled: Bool)
}

// MARK: - InMemoryReminderStore

/// A fully in-memory, `@Observable` implementation of `ReminderStore`.
///
/// Used by unit tests (inject directly). Mirrors `InMemoryAppearanceStore`:
/// defaults to disabled, an explicit initial value can be provided for tests
/// that need to start enabled.
@Observable
@MainActor
public final class InMemoryReminderStore: ReminderStore {

    public private(set) var isEnabled: Bool

    /// Creates a store with the default preference (disabled).
    public init() {
        self.isEnabled = false
    }

    /// Creates a store with an explicit initial preference.
    ///
    /// - Parameter isEnabled: The starting preference. Defaults to `false`.
    public init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    public func set(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
    }
}
