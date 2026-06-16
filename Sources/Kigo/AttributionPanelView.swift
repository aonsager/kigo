import SwiftUI

/// The attribution panel sheet presented when the user taps `info.entry` on the Today screen.
///
/// Introduced in slice #128 (C14). Displays the image title and credit line for the
/// current Kigo entry's associated image.
///
/// Accessibility identifiers (ADR 0013 Color.clear sentinel pattern for the root container):
/// - `info.panel` — root Color.clear layer (ZStack sentinel)
/// - `info.title` — Text showing attribution.title.ja
/// - `info.credit` — Text showing attribution.credit.ja
///
/// The root container uses the Color.clear sentinel pattern (ADR 0013) so that
/// `waitForExistence("info.panel")` targets only the clear layer, not child Text elements.
struct AttributionPanelView: View {
    let attribution: Attribution

    var body: some View {
        ZStack {
            // ADR 0013: Color.clear sentinel — applies the root identifier only to this layer,
            // not to child elements, so waitForExistence("info.panel") is unambiguous.
            Color.clear
                .accessibilityIdentifier("info.panel")

            VStack(spacing: 20) {
                // Attribution title
                Text(attribution.title.ja)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .padding(.top, 24)
                    .accessibilityIdentifier("info.title")

                Divider()

                // Credit line (photographer / source)
                Text(attribution.credit.ja)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .accessibilityIdentifier("info.credit")

                Spacer()
            }
        }
    }
}
