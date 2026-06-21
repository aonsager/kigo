import SwiftUI
import Foundation

// MARK: - PaywallView

/// The thin Paywall surface: presents the widget-access subscription product and a
/// Restore Purchases action. All presentation logic lives in `PaywallModel` so it is
/// testable headlessly with injected fakes (no `SKTestSession` / real StoreKit call —
/// see ADR 0009 / CLAUDE.md).
///
/// The purchase button surface exists here but no automated test drives a real
/// purchase. Real purchase flow requires a live StoreKit session and is exercised
/// only via the Xcode IDE run path, never on the CLI gating path.
///
/// Extended in slice #149 to apply KigoFont to UI-chrome text elements.
///
/// **Asagiri revamp**: restyled to the Settings → Widget section from
/// `Kigo Revamp.dc.html` §4 — a quiet "Kigo Widgets" label with the price aligned
/// right, the single honest benefit, a before → after mini-widget preview showing
/// the image the subscription reveals, an accent Subscribe button, a text Restore,
/// and small legal links. Copy and every `paywall.*` identifier are unchanged so the
/// paywall/settings UI-test contract holds.
public struct PaywallView: View {
    @State private var model: PaywallModel
    private let chromeStrings: ChromeStrings

    /// - Parameters:
    ///   - model: The paywall view model (injected for testability).
    ///   - chromeStrings: Locale-specific button labels derived from the active
    ///     `LanguagePreference`. Defaults to Japanese (the app's primary locale).
    public init(model: PaywallModel, chromeStrings: ChromeStrings = ChromeStrings(.japanese)) {
        _model = State(initialValue: model)
        self.chromeStrings = chromeStrings
    }

    public var body: some View {
        // `paywall.sheet` is isolated onto a transparent sentinel so it does not propagate
        // onto child Text identifiers on iOS 26 (ADR 0013 / slice #86).
        ZStack {
            Color.clear
                .accessibilityIdentifier("paywall.sheet")
                .accessibilityHidden(false)

            VStack(alignment: .leading, spacing: 0) {
                // Section header: "Kigo Widgets" label + price aligned right.
                HStack(alignment: .firstTextBaseline) {
                    Text("Kigo Widgets")
                        .font(KigoFont.zenKaku(.medium, size: 10.5, relativeTo: .caption2))
                        .tracking(4)
                        .textCase(.uppercase)
                        .foregroundStyle(KigoTheme.textTertiary)

                    Spacer()

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(model.price)
                            .font(KigoFont.mincho(.bold, size: 19, relativeTo: .title3))
                            .foregroundStyle(KigoTheme.inkKanji)
                            .accessibilityIdentifier("paywall.price")
                        Text(model.duration)
                            .font(KigoFont.zenKaku(.regular, size: 12, relativeTo: .caption))
                            .foregroundStyle(KigoTheme.textSecondary)
                            .accessibilityIdentifier("paywall.duration")
                    }
                }

                Text(model.productID)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(KigoTheme.textTertiary)
                    .padding(.top, 4)

                // Single honest benefit.
                Text("Reveal the seasonal illustration on your home screen widget.")
                    .font(KigoFont.zenKaku(.light, size: 14, relativeTo: .body))
                    .lineSpacing(8)
                    .foregroundStyle(KigoTheme.inkReading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                    .accessibilityIdentifier("paywall.benefits")

                // Before → after preview: plain word card → image-revealed card.
                MiniWidgetPreview()
                    .padding(.top, 18)

                if model.isActive {
                    // Premium / manage surface — shown instead of the buy button.
                    Label("Subscription active", systemImage: "checkmark.seal.fill")
                        .font(KigoFont.zenKaku(.medium, size: 15, relativeTo: .body))
                        .foregroundStyle(KigoTheme.premium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(KigoTheme.premium.opacity(0.12), in: RoundedRectangle(cornerRadius: KigoTheme.Radius.button))
                        .padding(.top, 20)
                        .accessibilityIdentifier("paywall.manage")
                } else {
                    // Accent Subscribe button.
                    Button {
                        Task { await model.buy() }
                    } label: {
                        Text("Subscribe")
                            .font(KigoFont.zenKaku(.medium, size: 15, relativeTo: .body))
                            .foregroundStyle(Color(red: 0.97, green: 0.95, blue: 0.92))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(KigoTheme.accent, in: RoundedRectangle(cornerRadius: KigoTheme.Radius.button))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 20)
                    .accessibilityIdentifier("paywall.buy")
                }

                Button(chromeStrings.restore) {
                    Task { await model.restore() }
                }
                .font(KigoFont.zenKaku(.regular, size: 13, relativeTo: .footnote))
                .foregroundStyle(KigoTheme.textSecondary)
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
                .accessibilityIdentifier("paywall.restore")

                Divider()
                    .overlay(KigoTheme.hairline)
                    .padding(.vertical, 18)

                // Legal links — placeholder URLs (ADR 0013 / J4).
                HStack(spacing: 16) {
                    Spacer()
                    Link("Terms of Use", destination: PaywallConfig.termsOfUseURL)
                        .font(KigoFont.zenKaku(.regular, size: 12, relativeTo: .caption))
                        .foregroundStyle(KigoTheme.textTertiary)
                        .accessibilityIdentifier("paywall.terms")

                    Text("·").foregroundStyle(KigoTheme.textTertiary)

                    Link("Privacy Policy", destination: PaywallConfig.privacyPolicyURL)
                        .font(KigoFont.zenKaku(.regular, size: 12, relativeTo: .caption))
                        .foregroundStyle(KigoTheme.textTertiary)
                        .accessibilityIdentifier("paywall.privacy")
                    Spacer()
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
        }
        .task { await model.loadState() }
    }
}

// MARK: - MiniWidgetPreview

/// The "non-subscribed → subscribed" widget illustration: a plain word-only card,
/// an arrow, then an image-revealed card. Decorative (no accessibility identifiers).
private struct MiniWidgetPreview: View {
    var body: some View {
        HStack(spacing: 12) {
            // Basic: paper card, word only.
            VStack(spacing: 5) {
                Text("季")
                    .font(KigoFont.mincho(.semibold, size: 22, relativeTo: .title2))
                    .foregroundStyle(KigoTheme.inkKo)
                Text("きご")
                    .font(KigoFont.zenKaku(.regular, size: 8, relativeTo: .caption2))
                    .tracking(1)
                    .foregroundStyle(KigoTheme.textTertiary)
            }
            .frame(width: 74, height: 74)
            .background(KigoTheme.canvas, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(KigoTheme.hairline, lineWidth: 1))

            Image(systemName: "arrow.right")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(KigoTheme.textTertiary)

            // Premium: image-revealed card.
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [Color(red: 0.54, green: 0.58, blue: 0.52), Color(red: 0.31, green: 0.35, blue: 0.30)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                LinearGradient(
                    colors: [.clear, .black.opacity(0.45)],
                    startPoint: .center, endPoint: .bottom
                )
                Text("季")
                    .font(KigoFont.mincho(.semibold, size: 18, relativeTo: .title3))
                    .foregroundStyle(.white)
                    .padding(8)
            }
            .frame(width: 74, height: 74)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Text("Subscribe to reveal the image.")
                .font(KigoFont.zenKaku(.light, size: 11.5, relativeTo: .caption))
                .lineSpacing(3)
                .foregroundStyle(KigoTheme.textSecondary)
        }
    }
}
