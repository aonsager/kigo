import Foundation
import Observation

// MARK: - UserDefaultsReminderStore

/// A `UserDefaults`-backed implementation of `ReminderStore`.
///
/// Persists the user's daily-reminder preference across app launches using a
/// named UserDefaults suite. A **named** suite (rather than `.standard`) is
/// mandatory so unit tests can create a fresh, isolated suite per test —
/// preventing state bleed between tests. Mirrors `UserDefaultsAppearanceStore`.
///
/// Fallback: an absent key (a fresh install / unset preference) reads back
/// `false` — the daily reminder is default-**off** (ADR 0019 / C23).
@Observable
@MainActor
public final class UserDefaultsReminderStore: ReminderStore {

    // MARK: - Defaults key

    /// The UserDefaults key under which the reminder preference is stored.
    public static let defaultsKey = "kigo.dailyReminderEnabled"

    // MARK: - Observable state

    public private(set) var isEnabled: Bool

    // MARK: - Private

    private let defaults: UserDefaults

    // MARK: - Init

    /// Creates a store backed by the named UserDefaults suite.
    ///
    /// - Parameter suiteName: The UserDefaults suite name. Using a unique suite per
    ///   test prevents state bleed between test runs. The production app uses a fixed
    ///   suite name (e.g. "com.tomeitotameigo.kigo").
    public init(suiteName: String) {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        self.defaults = defaults
        // `bool(forKey:)` returns false for an absent key, which is exactly the
        // desired default-off semantics for an unset store.
        self.isEnabled = defaults.bool(forKey: UserDefaultsReminderStore.defaultsKey)
    }

    // MARK: - ReminderStore

    public func set(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
        defaults.set(isEnabled, forKey: UserDefaultsReminderStore.defaultsKey)
    }
}
