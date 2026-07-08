import Foundation

// MARK: - launchLanguageStore

/// Resolves the `LanguageStore` to use at app launch, reading `KIGO_FAKE_LANGUAGE`
/// from the launch environment.
///
/// Mirrors the ADR 0013 resolver pattern used by `launchDateProvider`, `launchEntitlementProvider`,
/// and `launchOfferDisplay`: pure function, takes a `[String: String]` dictionary so unit
/// tests can exercise all branches without launching the app.
///
/// Resolution rules:
/// - `KIGO_FAKE_LANGUAGE=en` → a locked `InMemoryLanguageStore` pinned to `.english`.
///   `set(_:)` calls are silently ignored so tests cannot accidentally mutate the value.
/// - `KIGO_FAKE_LANGUAGE=ja` → a locked `InMemoryLanguageStore` pinned to `.japanese`.
/// - absent or unrecognised  → `UserDefaultsLanguageStore` (production, persisted),
///   seeded — when the user has not yet chosen a language — from the OS preferred
///   languages via `initialLanguagePreference(preferredLanguages:)` (falling back to
///   English). A preference the user has actually set persists and always wins over
///   the OS-derived seed.
///
/// - Parameter environment: The launch-environment dictionary, typically
///   `ProcessInfo.processInfo.environment` at the app root.
/// - Returns: The resolved `LanguageStore` (one of `LockedInMemoryLanguageStore` or
///   `UserDefaultsLanguageStore`).
@MainActor
public func launchLanguageStore(environment: [String: String]) -> any LanguageStore {
    #if DEBUG
    // Test-only seam: KIGO_FAKE_LANGUAGE is honoured in DEBUG builds only (H1).
    switch environment["KIGO_FAKE_LANGUAGE"] {
    case "en":
        return LockedInMemoryLanguageStore(preference: .english)
    case "ja":
        return LockedInMemoryLanguageStore(preference: .japanese)
    default:
        break
    }
    #endif
    let osDefault = initialLanguagePreference(preferredLanguages: Locale.preferredLanguages)
    return UserDefaultsLanguageStore(suiteName: "com.tomeitotameigo.kigo", systemDefault: osDefault)
}

// MARK: - initialLanguagePreference

/// Derives the language a *fresh install* should start in from the OS's ordered list
/// of preferred languages, **falling back to English** when the OS expresses no
/// supported preference.
///
/// The app supports two languages (`ja`, `en`). We walk the OS list in priority order
/// and return the first supported match — Japanese if the user prefers Japanese,
/// English if they prefer English — exactly mirroring how iOS itself picks an app's
/// language from `Locale.preferredLanguages` against its supported set. Any language
/// the app does not support (e.g. `fr`) is skipped; if nothing matches, English is the
/// fallback.
///
/// Pure over its input (mirrors `launchDateProvider` / `launchOfferDisplay`) so it is
/// unit-tested deterministically without depending on the test host's locale.
///
/// - Parameter preferredLanguages: BCP-47 language identifiers in priority order,
///   typically `Locale.preferredLanguages`.
/// - Returns: `.japanese` if Japanese is the top supported preference, otherwise `.english`.
public func initialLanguagePreference(preferredLanguages: [String]) -> LanguagePreference {
    for identifier in preferredLanguages {
        let code = identifier.lowercased()
        if code == "ja" || code.hasPrefix("ja-") || code.hasPrefix("ja_") {
            return .japanese
        }
        if code == "en" || code.hasPrefix("en-") || code.hasPrefix("en_") {
            return .english
        }
    }
    return .english
}

#if DEBUG

// MARK: - LockedInMemoryLanguageStore (DEBUG-only test seam)

/// An `@Observable` `LanguageStore` whose preference is pinned at construction time
/// and silently ignores `set(_:)` calls.
///
/// Used by `launchLanguageStore` for the `KIGO_FAKE_LANGUAGE` injection path.
/// The "locked" semantic ensures UI tests cannot accidentally change the pinned value
/// by navigating the settings flow — the store stays at its initial preference for the
/// entire test session.
@Observable
@MainActor
public final class LockedInMemoryLanguageStore: LanguageStore {

    public private(set) var preference: LanguagePreference

    public init(preference: LanguagePreference) {
        self.preference = preference
    }

    /// No-op — the store is locked; the preference cannot be changed after construction.
    public func set(_ preference: LanguagePreference) {
        // Intentionally ignored.
    }
}

#endif
