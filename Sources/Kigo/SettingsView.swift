import SwiftUI

// MARK: - SettingsView

/// The Settings sheet, introduced in Slice #138.
///
/// Combines a JP/EN language-preference picker (`settings.language`) with the
/// existing `PaywallView`. RootView presents this instead of `PaywallView`
/// directly so users can switch language and see the paywall chrome update
/// reactively in the same session.
///
/// Reactivity pattern:
///  - `@State var currentLanguage` is initialised from `languageStore.preference`
///    at view creation.
///  - The segmented `Picker` drives `currentLanguage`; SwiftUI re-renders
///    `PaywallView` with the new `ChromeStrings` on every change.
///  - `.onChange(of:)` propagates each change to `languageStore` for persistence.
///
/// `any LanguageStore` is intentional: `@State` owns the reactive copy; the
/// store is only the persistence back-end (ADR 0013).
struct SettingsView: View {
    let model: PaywallModel
    let languageStore: any LanguageStore

    @State private var currentLanguage: LanguagePreference

    init(model: PaywallModel, languageStore: any LanguageStore) {
        self.model = model
        self.languageStore = languageStore
        // Capture the store's preference at init time into @State.
        _currentLanguage = State(initialValue: languageStore.preference)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Language", selection: $currentLanguage) {
                Text("Japanese").tag(LanguagePreference.japanese)
                Text("English").tag(LanguagePreference.english)
            }
            .pickerStyle(.segmented)
            .padding()
            .accessibilityIdentifier("settings.language")

            PaywallView(
                model: model,
                chromeStrings: ChromeStrings(currentLanguage)
            )
        }
        .onChange(of: currentLanguage) { _, newValue in
            languageStore.set(newValue)
        }
    }
}
