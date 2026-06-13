import SwiftUI

/// Today screen — renders the Kigo kanji, hiragana reading, prose description,
/// and the current Microseason (Kō and Sekki) for the resolved date.
///
/// Extended in slice #57 to add reading (`kigo.reading`) and description
/// (`kigo.description`) beneath the kanji. The view takes the already-resolved
/// `ResolvedDay` as input and performs no loading or date resolution itself.
///
/// Extended in slice #58 to add the Microseason section:
/// - `microseason.ko`: The Kō reading (hiragana) as the primary label — e.g.
///   "くされたるくさほたるとなる". The hiragana reading is chosen over kanji because
///   it is consistently readable at a glance and matches the display style used
///   for the Kigo reading above.
/// - `microseason.sekki`: The parent Sekki reading (hiragana) as a secondary label
///   — e.g. "ぼうしゅ". Shown beneath the Kō with a smaller, secondary font weight
///   to signal the containing solar term.
///
/// Additional fields (image) are out of scope — see slice #59.
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

            Divider()
                .padding(.vertical, 4)

            // Microseason section — Kō as primary, Sekki as secondary.
            // Text representation: hiragana reading for both, consistent with
            // the Kigo reading style above.
            Text(resolvedDay.ko.reading)
                .font(.headline)
                .accessibilityIdentifier("microseason.ko")

            Text(resolvedDay.sekki.reading)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("microseason.sekki")
        }
    }
}
