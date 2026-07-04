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
/// Fallback: when no valid preference has been persisted yet (absent or unrecognised
/// raw string) the store reports the injected `systemDefault` — the OS-derived initial
/// language — **without persisting it**. Only an explicit `set(_:)` (a manual user
/// choice) writes to defaults, so once the user picks a language it is preserved and
/// always wins over the OS-derived default on subsequent launches.
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
    /// - Parameters:
    ///   - suiteName: The UserDefaults suite name. Using a unique suite per test
    ///     prevents state bleed between test runs. The production app uses a fixed
    ///     suite name (e.g. "com.tomeitotameigo.kigo").
    ///   - systemDefault: The preference to report when nothing valid has been
    ///     persisted yet — the OS-derived initial language (English fallback), resolved
    ///     by `initialLanguagePreference(preferredLanguages:)` at the launch call site.
    ///     Defaults to `.japanese` for callers/tests that don't care about the seed.
    ///     This value is **not** written to defaults: only `set(_:)` persists.
    public init(suiteName: String, systemDefault: LanguagePreference = .japanese) {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        self.defaults = defaults
        // A persisted, decodable value always wins (a preference the user has set);
        // otherwise report the injected systemDefault without persisting it.
        if let raw = defaults.string(forKey: UserDefaultsLanguageStore.defaultsKey),
           let decoded = LanguagePreference(rawValue: raw) {
            self.preference = decoded
        } else {
            self.preference = systemDefault
        }
    }

    // MARK: - LanguageStore

    public func set(_ preference: LanguagePreference) {
        self.preference = preference
        defaults.set(preference.rawValue, forKey: UserDefaultsLanguageStore.defaultsKey)
    }
}
