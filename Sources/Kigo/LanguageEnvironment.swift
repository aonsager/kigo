import KigoCore
import SwiftUI

// MARK: - LanguagePreferenceKey

/// SwiftUI environment key that propagates the active `LanguagePreference` through the view tree.
///
/// Default is `.japanese` so any view without an explicit `.environment(\.language, …)` injection
/// renders Japanese text — the same as the app's startup default.
///
/// Usage:
///   Inject:  `.environment(\.language, language)` on a parent view.
///   Consume: `@Environment(\.language) private var language`
struct LanguagePreferenceKey: EnvironmentKey {
    static let defaultValue: LanguagePreference = .japanese
}

extension EnvironmentValues {
    /// The user's active language preference, propagated via the SwiftUI environment.
    var language: LanguagePreference {
        get { self[LanguagePreferenceKey.self] }
        set { self[LanguagePreferenceKey.self] = newValue }
    }
}
