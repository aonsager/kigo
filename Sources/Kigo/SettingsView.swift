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
///  - `@State var currentLanguage` is initialised from `languageStore.preference`.
///  - The segmented `Picker` drives `currentLanguage`; SwiftUI re-renders
///    `PaywallView` with the new `ChromeStrings` on every change.
///  - `.onChange(of:)` propagates each change to `languageStore` for persistence.
///
/// `any LanguageStore` is intentional: `@State` owns the reactive copy; the
/// store is only the persistence back-end (ADR 0013).
///
/// **Asagiri revamp**: wrapped in the shared sheet surface with a grab handle and
/// a 設定 (Settings) Mincho title above a 言語 (Language) segmented control, per
/// `Kigo Revamp.dc.html` §3. The segment labels remain the exact strings
/// "Japanese"/"English" that the language UI tests assert against.
struct SettingsView: View {
    let model: PaywallModel
    @Binding var language: LanguagePreference
    let languageStore: any LanguageStore
    let appearanceStore: any AppearanceStore

    @State private var currentAppearance: AppearancePreference

    init(
        model: PaywallModel,
        language: Binding<LanguagePreference>,
        languageStore: any LanguageStore,
        appearanceStore: any AppearanceStore
    ) {
        self.model = model
        self._language = language
        self.languageStore = languageStore
        self.appearanceStore = appearanceStore
        _currentAppearance = State(initialValue: appearanceStore.preference)
    }

    var body: some View {
        VStack(spacing: 0) {
                GrabHandle()
                    .padding(.top, 10)
                    .padding(.bottom, 18)

                Text("設定")
                    .font(KigoFont.mincho(.bold, size: 21, relativeTo: .title2))
                    .foregroundStyle(KigoTheme.inkKanji)

                VStack(alignment: .leading, spacing: 12) {
                    Text("言語")
                        .font(KigoFont.zenKaku(.medium, size: 10.5, relativeTo: .caption2))
                        .tracking(4)
                        .foregroundStyle(KigoTheme.textTertiary)

                    Picker("Language", selection: $language) {
                        Text("Japanese").tag(LanguagePreference.japanese)
                        Text("English").tag(LanguagePreference.english)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("settings.language")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 26)

                VStack(alignment: .leading, spacing: 12) {
                    Text("表示")
                        .font(KigoFont.zenKaku(.medium, size: 10.5, relativeTo: .caption2))
                        .tracking(4)
                        .foregroundStyle(KigoTheme.textTertiary)

                    Picker("Appearance", selection: $currentAppearance) {
                        Text("System").tag(AppearancePreference.system)
                        Text("Light").tag(AppearancePreference.light)
                        Text("Dark").tag(AppearancePreference.dark)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("settings.appearance")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 22)

                Divider()
                    .overlay(KigoTheme.hairline)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 22)

                PaywallView(
                    model: model,
                    chromeStrings: ChromeStrings(language)
                )
        }
        .padding(.bottom, 28)
        .onChange(of: language) { _, newValue in
            languageStore.set(newValue)
        }
        .onChange(of: currentAppearance) { _, newValue in
            appearanceStore.set(newValue)
        }
    }
}
