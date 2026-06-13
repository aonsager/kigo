import SwiftUI

/// Today screen — renders the Kigo kanji, hiragana reading, and prose
/// description for the resolved date.
///
/// Extended in slice #57 to add reading (`kigo.reading`) and description
/// (`kigo.description`) beneath the kanji. The view takes the already-resolved
/// `ResolvedDay` as input and performs no loading or date resolution itself.
///
/// Additional fields (image, Kō, Sekki) are out of scope — see slices #58–#60.
struct TodayView: View {
    let resolvedDay: ResolvedDay

    var body: some View {
        VStack(spacing: 8) {
            Text(resolvedDay.kigoEntry.kanji)
                .font(.largeTitle)
                .accessibilityIdentifier("kigo.kanji")

            Text(resolvedDay.kigoEntry.reading)
                .font(.title2)
                .accessibilityIdentifier("kigo.reading")

            Text(resolvedDay.kigoEntry.description)
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .accessibilityIdentifier("kigo.description")
        }
    }
}
