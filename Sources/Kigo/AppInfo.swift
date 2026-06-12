import Foundation

/// Static metadata about the Kigo app.
/// Provides testable, non-tautological values the smoke tests can assert against.
enum AppInfo {
    /// The canonical bundle identifier for the Kigo app (matches GOAL.md / ADR 0002).
    static let bundleIdentifier: String = "com.tomeitotameigo.kigo"

    /// The human-readable display name for the app.
    static let displayName: String = "Kigo"
}
