import Foundation
import Observation

// MARK: - UserDefaultsLanguageStore

/// A `UserDefaults`-backed implementation of `LanguageStore`.
///
/// Persists the user's language preference across app launches using a named
/// UserDefaults suite. A **named** suite (rather than `.standard`) is mandatory
/// so unit tests can create a fresh, isolated suite per test — preventing
/// state bleed between tests (see `LanguagePreferenceTests` / ADR 0013 pattern).
///
/// Fallback: any absent or unrecognised raw string returns `.japanese`.
@Observable
@MainActor
public final class UserDefaultsLanguageStore: LanguageStore {

    // MARK: - Defaults key

    /// The UserDefaults key under which the language preference raw value is stored.
    ///
    /// Exposed as `public` so tests can pre-seed or inspect the raw defaults value.
    public static let defaultsKey = "kigo.languagePreference"

    // MARK: - Observable state

    public private(set) var preference: LanguagePreference

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
        // Decode the stored raw value; unknown/absent → .japanese.
        if let raw = defaults.string(forKey: UserDefaultsLanguageStore.defaultsKey),
           let decoded = LanguagePreference(rawValue: raw) {
            self.preference = decoded
        } else {
            self.preference = .japanese
        }
    }

    // MARK: - LanguageStore

    public func set(_ preference: LanguagePreference) {
        self.preference = preference
        defaults.set(preference.rawValue, forKey: UserDefaultsLanguageStore.defaultsKey)
    }
}
