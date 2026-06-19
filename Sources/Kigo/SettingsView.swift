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
    let languageStore: any LanguageStore

    @State private var currentLanguage: LanguagePreference

    init(model: PaywallModel, languageStore: any LanguageStore) {
        self.model = model
        self.languageStore = languageStore
        _currentLanguage = State(initialValue: languageStore.preference)
    }

    var body: some View {
        ScrollView {
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

                    Picker("Language", selection: $currentLanguage) {
                        Text("Japanese").tag(LanguagePreference.japanese)
                        Text("English").tag(LanguagePreference.english)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("settings.language")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 26)

                Divider()
                    .overlay(KigoTheme.hairline)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 22)

                PaywallView(
                    model: model,
                    chromeStrings: ChromeStrings(currentLanguage)
                )
            }
            .padding(.bottom, 28)
        }
        .presentationBackground(KigoTheme.sheetSurface)
        .presentationDragIndicator(.hidden)
        .onChange(of: currentLanguage) { _, newValue in
            languageStore.set(newValue)
        }
    }
}
