import Foundation
import Observation

// MARK: - launchReminderStore

/// Resolves the `ReminderStore` to use at app launch, reading `KIGO_FAKE_REMINDER`
/// from the launch environment (Slice #220, PRD #218, C23, ADR 0013 resolver pattern).
///
/// Resolution rules:
/// - `KIGO_FAKE_REMINDER=on`  → a locked `LockedInMemoryReminderStore` seeded enabled.
/// - `KIGO_FAKE_REMINDER=off` → a locked `LockedInMemoryReminderStore` seeded disabled.
/// - absent / unrecognised     → `UserDefaultsReminderStore` (production, persisted,
///   default-off).
///
/// The `=on` seed exists so a **real UI-test app launch** can show the Settings
/// toggle in its "on" state without ever tapping it — tapping would fire the real
/// notification-permission prompt, which hangs headlessly (ADR 0019 / J9). This
/// mirrors `launchAppearanceStore`'s `KIGO_FAKE_APPEARANCE` locked-store path.
///
/// - Parameter environment: The launch-environment dictionary, typically
///   `ProcessInfo.processInfo.environment` at the app root.
@MainActor
public func launchReminderStore(environment: [String: String]) -> any ReminderStore {
    #if DEBUG
    // Test-only seam: KIGO_FAKE_REMINDER is honoured in DEBUG builds only (H1).
    switch environment["KIGO_FAKE_REMINDER"] {
    case "on":
        return LockedInMemoryReminderStore(isEnabled: true)
    case "off":
        return LockedInMemoryReminderStore(isEnabled: false)
    default:
        break
    }
    #endif
    return UserDefaultsReminderStore(suiteName: "com.tomeitotameigo.kigo")
}

#if DEBUG

// MARK: - LockedInMemoryReminderStore (DEBUG-only test seam)

/// An `@Observable` `ReminderStore` whose preference is pinned at construction time
/// and silently ignores `set(_:)`.
///
/// Used by `launchReminderStore` for the `KIGO_FAKE_REMINDER` injection path: a UI
/// test cannot accidentally change the seeded value by navigating Settings, so the
/// toggle stays in its intended state for the whole session. Mirrors
/// `LockedInMemoryAppearanceStore`.
@Observable
@MainActor
public final class LockedInMemoryReminderStore: ReminderStore {

    public private(set) var isEnabled: Bool

    public init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    /// No-op — the store is locked; the preference cannot change after construction.
    public func set(_ isEnabled: Bool) {
        // Intentionally ignored.
    }
}

#endif
