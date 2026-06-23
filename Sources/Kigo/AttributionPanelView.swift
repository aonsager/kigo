import SwiftUI

/// The attribution panel sheet presented when the user taps `info.entry` on the Today screen.
///
/// Introduced in slice #128 (C14). **Asagiri revamp**: restyled to the quiet
/// image-credit panel from `Kigo Revamp.dc.html` §6 — image title (Mincho), a
/// 写真 credit line, and a license/source line, over the shared sheet surface, with
/// a grab indicator and no header/close button (dismiss via grab or backdrop).
///
/// Extended in slice #176 to honour `@Environment(\.language)` — title, credit, and
/// license now use `localized(for: language)` so the panel updates live after a
/// Settings language toggle.
///
/// Accessibility identifiers (ADR 0013 Color.clear sentinel pattern):
/// - `info.panel` — root Color.clear layer (ZStack sentinel)
/// - `info.title` — Text showing attribution.title localized for the active language
/// - `info.credit` — Text showing attribution.credit localized for the active language
/// - `info.license` — Text showing attribution.license localized for the active language
struct AttributionPanelView: View {
    let attribution: Attribution

    @Environment(\.language) private var language

    var body: some View {
        ZStack {
            // ADR 0013: Color.clear sentinel — applies the root identifier only to this layer.
            Color.clear
                .accessibilityIdentifier("info.panel")

            VStack(alignment: .leading, spacing: 0) {
                GrabHandle()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                    .padding(.bottom, 20)

                Text(attribution.title.localized(for: language))
                    .font(KigoFont.mincho(.medium, size: 16, relativeTo: .headline))
                    .foregroundStyle(KigoTheme.inkKanji)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("info.title")

                Text(attribution.credit.localized(for: language))
                    .font(KigoFont.zenKaku(.regular, size: 13, relativeTo: .footnote))
                    .foregroundStyle(KigoTheme.inkReading)
                    .padding(.top, 8)
                    .accessibilityIdentifier("info.credit")

                Text(attribution.license.localized(for: language))
                    .font(KigoFont.zenKaku(.regular, size: 11.5, relativeTo: .caption))
                    .foregroundStyle(KigoTheme.textTertiary)
                    .padding(.top, 10)
                    .accessibilityIdentifier("info.license")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 30)
            .padding(.bottom, 40)
        }
    }
}
