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
/// - absent or unrecognised  → `UserDefaultsLanguageStore` (production, persisted).
///
/// - Parameter environment: The launch-environment dictionary, typically
///   `ProcessInfo.processInfo.environment` at the app root.
/// - Returns: The resolved `LanguageStore` (one of `LockedInMemoryLanguageStore` or
///   `UserDefaultsLanguageStore`).
@MainActor
public func launchLanguageStore(environment: [String: String]) -> any LanguageStore {
    switch environment["KIGO_FAKE_LANGUAGE"] {
    case "en":
        return LockedInMemoryLanguageStore(preference: .english)
    case "ja":
        return LockedInMemoryLanguageStore(preference: .japanese)
    default:
        return UserDefaultsLanguageStore(suiteName: "com.tomeitotameigo.kigo")
    }
}

// MARK: - LockedInMemoryLanguageStore

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
