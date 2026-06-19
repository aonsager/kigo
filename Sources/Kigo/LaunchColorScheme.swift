import SwiftUI

// MARK: - launchColorScheme

/// Resolves the optional `ColorScheme` to apply at app launch, reading
/// `KIGO_FAKE_APPEARANCE` from the launch environment.
///
/// Mirrors the ADR 0013 resolver pattern used by `launchDateProvider`,
/// `launchLanguageStore`, and friends: pure function, takes a `[String: String]`
/// dictionary so unit tests can exercise all branches without launching the app.
///
/// Resolution rules:
/// - `KIGO_FAKE_APPEARANCE=dark`   → `.dark`
/// - `KIGO_FAKE_APPEARANCE=light`  → `.light`
/// - absent or unrecognised         → `nil` (let the system decide)
///
/// The resolved value is applied via `.preferredColorScheme(_:)` on the root
/// `WindowGroup` view in `KigoApp.body` (slice #144).
///
/// - Parameter environment: The launch-environment dictionary, typically
///   `ProcessInfo.processInfo.environment` at the app root.
/// - Returns: `.dark`, `.light`, or `nil` when the key is absent or unrecognised.
public func launchColorScheme(environment: [String: String]) -> ColorScheme? {
    switch environment["KIGO_FAKE_APPEARANCE"] {
    case "dark":
        return .dark
    case "light":
        return .light
    default:
        return nil
    }
}
