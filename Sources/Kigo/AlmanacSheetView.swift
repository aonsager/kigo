import SwiftUI

/// The almanac sheet presented when the user taps `microseason.timeline` on the Today screen.
///
/// Introduced in slice #123 (C13). Displays the current Kō's almanac position, a day-within-Kō
/// progress gauge, and the Kō's Japanese prose description.
///
/// Accessibility identifiers (ADR 0013 Color.clear sentinel pattern for the root container):
/// - `microseason.almanac` — root Color.clear layer (ZStack sentinel)
/// - `microseason.koPosition` — Text showing e.g. "27 / 72"
/// - `microseason.dayGauge` — ProgressView tracking dayWithinKo / koRangeLength
/// - `microseason.koDescription` — Text showing ko.description.ja
///
/// The root container uses the Color.clear sentinel pattern (ADR 0013) so that
/// `waitForExistence("microseason.almanac")` targets only the clear layer, not child Text elements.
struct AlmanacSheetView: View {
    let almanacPositions: AlmanacPositions
    let ko: Ko

    var body: some View {
        ZStack {
            // ADR 0013: Color.clear sentinel — applies the root identifier only to this layer,
            // not to child elements, so waitForExistence("microseason.almanac") is unambiguous.
            Color.clear
                .accessibilityIdentifier("microseason.almanac")

            VStack(spacing: 20) {
                // Ko name header
                Text(ko.kanji)
                    .font(.title)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .padding(.top, 24)

                Text(ko.reading)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Divider()

                // Year position: e.g. "27 / 72"
                Text("\(almanacPositions.koYearPosition) / \(almanacPositions.koYearTotal)")
                    .font(.headline)
                    .accessibilityIdentifier("microseason.koPosition")

                // Day-within-Kō progress gauge
                ProgressView(
                    value: Double(almanacPositions.dayWithinKo),
                    total: Double(almanacPositions.koRangeLength)
                )
                .progressViewStyle(.linear)
                .padding(.horizontal, 32)
                .accessibilityIdentifier("microseason.dayGauge")

                // Ko description in Japanese
                Text(ko.description.ja)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .accessibilityIdentifier("microseason.koDescription")

                Spacer()
            }
        }
    }
}
