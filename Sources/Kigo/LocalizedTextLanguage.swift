import Foundation

// MARK: - LocalizedText + LanguagePreference

extension LocalizedText {
    /// Returns the localised string for the given `LanguagePreference`.
    ///
    /// - `.english`: returns `en` when present, falling back to `ja` when `en` is nil.
    /// - `.japanese`: always returns `ja`.
    ///
    /// This is in a separate file (not `Manifest.swift`) so the widget extension,
    /// which compiles `Manifest.swift` in isolation, does not need to also compile
    /// `LanguagePreference.swift` (which carries a SwiftUI import). The widget
    /// does not use `localized(for:)` — it always renders Japanese.
    public func localized(for preference: LanguagePreference) -> String {
        switch preference {
        case .english:
            return en ?? ja
        case .japanese:
            return ja
        }
    }
}
