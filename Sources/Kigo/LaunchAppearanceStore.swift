import SwiftUI

// MARK: - launchAppearanceStore

/// Resolves the `AppearanceStore` to use at app launch, reading `KIGO_FAKE_APPEARANCE`
/// from the launch environment.
///
/// Mirrors the ADR 0013 resolver pattern used by `launchLanguageStore`: pure function,
/// takes a `[String: String]` dictionary so unit tests can exercise all branches without
/// launching the app.
///
/// Resolution rules:
/// - `KIGO_FAKE_APPEARANCE=dark`  → a locked `InMemoryAppearanceStore` pinned to `.dark`.
/// - `KIGO_FAKE_APPEARANCE=light` → a locked `InMemoryAppearanceStore` pinned to `.light`.
/// - absent or unrecognised        → `UserDefaultsAppearanceStore` (production, persisted,
///   default `.system`).
///
/// The lock is derived from `launchColorScheme(environment:)` so the fake-appearance
/// semantics stay in a single place: `DarkModeUITests` (which launches with
/// `KIGO_FAKE_APPEARANCE=dark`) still forces dark, and `set(_:)` is silently ignored
/// so navigating the settings flow cannot unpin the value during a UI test.
///
/// - Parameter environment: The launch-environment dictionary, typically
///   `ProcessInfo.processInfo.environment` at the app root.
/// - Returns: The resolved `AppearanceStore` (one of `LockedInMemoryAppearanceStore` or
///   `UserDefaultsAppearanceStore`).
@MainActor
public func launchAppearanceStore(environment: [String: String]) -> any AppearanceStore {
    switch launchColorScheme(environment: environment) {
    case .dark:
        return LockedInMemoryAppearanceStore(preference: .dark)
    case .light:
        return LockedInMemoryAppearanceStore(preference: .light)
    case .none:
        return UserDefaultsAppearanceStore(suiteName: "com.tomeitotameigo.kigo")
    @unknown default:
        return UserDefaultsAppearanceStore(suiteName: "com.tomeitotameigo.kigo")
    }
}

// MARK: - LockedInMemoryAppearanceStore

/// An `@Observable` `AppearanceStore` whose preference is pinned at construction time
/// and silently ignores `set(_:)` calls.
///
/// Used by `launchAppearanceStore` for the `KIGO_FAKE_APPEARANCE` injection path.
/// The "locked" semantic ensures UI tests cannot accidentally change the pinned value
/// by navigating the settings flow — the store stays at its initial preference for the
/// entire test session. Mirrors `LockedInMemoryLanguageStore`.
@Observable
@MainActor
public final class LockedInMemoryAppearanceStore: AppearanceStore {

    public private(set) var preference: AppearancePreference

    public init(preference: AppearancePreference) {
        self.preference = preference
    }

    /// No-op — the store is locked; the preference cannot be changed after construction.
    public func set(_ preference: AppearancePreference) {
        // Intentionally ignored.
    }
}
