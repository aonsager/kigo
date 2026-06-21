import Foundation
import Observation

// MARK: - UserDefaultsAppearanceStore

/// A `UserDefaults`-backed implementation of `AppearanceStore`.
///
/// Persists the user's appearance preference across app launches using a named
/// UserDefaults suite. A **named** suite (rather than `.standard`) is mandatory
/// so unit tests can create a fresh, isolated suite per test — preventing state
/// bleed between tests. Mirrors `UserDefaultsLanguageStore`.
///
/// Fallback: any absent or unrecognised raw string returns `.system`.
@Observable
@MainActor
public final class UserDefaultsAppearanceStore: AppearanceStore {

    // MARK: - Defaults key

    /// The UserDefaults key under which the appearance preference raw value is stored.
    public static let defaultsKey = "kigo.appearancePreference"

    // MARK: - Observable state

    public private(set) var preference: AppearancePreference

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
        if let raw = defaults.string(forKey: UserDefaultsAppearanceStore.defaultsKey),
           let decoded = AppearancePreference(rawValue: raw) {
            self.preference = decoded
        } else {
            self.preference = .system
        }
    }

    // MARK: - AppearanceStore

    public func set(_ preference: AppearancePreference) {
        self.preference = preference
        defaults.set(preference.rawValue, forKey: UserDefaultsAppearanceStore.defaultsKey)
    }
}
