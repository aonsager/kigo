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

                // Subscription status + restore only — the buy/marketing flow lives in
                // the separate purchase sheet (PRD #189). Restore stays reachable here
                // for every user (Apple requirement), Premium or Basic.
                SubscriptionStrip(model: model, chromeStrings: ChromeStrings(language))
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

// MARK: - SubscriptionStrip

/// The slim subscription surface inside Settings (PRD #189): status + Restore + legal.
/// It carries the `paywall.sheet` sentinel (so the Settings sheet is still discoverable
/// by the paywall/language UI tests) and `paywall.restore` (Apple requires Restore to
/// be reachable by every user, Premium or Basic) — but NOT the marketing/`paywall.buy`
/// flow, which now lives only in the dedicated purchase sheet.
///
/// The `paywall.sheet` identifier is isolated onto a transparent sentinel so it does not
/// propagate onto child Text identifiers on iOS 26 (ADR 0013 / slice #86).
private struct SubscriptionStrip: View {
    let model: PaywallModel
    let chromeStrings: ChromeStrings

    var body: some View {
        ZStack {
            Color.clear
                .accessibilityIdentifier("paywall.sheet")
                .accessibilityHidden(false)

            VStack(alignment: .leading, spacing: 12) {
                Text("購読")
                    .font(KigoFont.zenKaku(.medium, size: 10.5, relativeTo: .caption2))
                    .tracking(4)
                    .foregroundStyle(KigoTheme.textTertiary)

                if model.isActive {
                    Label("Subscription active", systemImage: "checkmark.seal.fill")
                        .font(KigoFont.zenKaku(.medium, size: 15, relativeTo: .body))
                        .foregroundStyle(KigoTheme.premium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("paywall.manage")
                } else {
                    Text("Understanding is a one-time unlock, offered from today’s kigo.")
                        .font(KigoFont.zenKaku(.light, size: 13, relativeTo: .footnote))
                        .lineSpacing(4)
                        .foregroundStyle(KigoTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(chromeStrings.restore) {
                    Task { await model.restore() }
                }
                .font(KigoFont.zenKaku(.regular, size: 13, relativeTo: .footnote))
                .foregroundStyle(KigoTheme.textSecondary)
                .buttonStyle(.plain)
                .padding(.top, 4)
                .accessibilityIdentifier("paywall.restore")

                HStack(spacing: 16) {
                    Link("Terms of Use", destination: PaywallConfig.termsOfUseURL)
                        .accessibilityIdentifier("paywall.terms")
                    Text("·").foregroundStyle(KigoTheme.textTertiary)
                    Link("Privacy Policy", destination: PaywallConfig.privacyPolicyURL)
                        .accessibilityIdentifier("paywall.privacy")
                }
                .font(KigoFont.zenKaku(.regular, size: 12, relativeTo: .caption))
                .foregroundStyle(KigoTheme.textTertiary)
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
        }
        .task { await model.loadState() }
    }
}
