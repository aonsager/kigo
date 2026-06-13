import SwiftUI

/// Minimal Today screen for slice #55 (walking skeleton).
///
/// Displays the Kigo kanji for the resolved date. The kanji `Text` carries
/// the accessibility identifier `kigo.kanji` so the UI test can assert
/// its presence and non-empty content, proving the full launch→load→resolve→render
/// path executes on the warm bundled path.
///
/// Additional fields (reading, description, image, Kō, Sekki) are out of
/// scope for this slice — see slices #57–#60.
struct TodayView: View {
    let resolvedDay: ResolvedDay

    var body: some View {
        VStack {
            Text(resolvedDay.kigoEntry.kanji)
                .font(.largeTitle)
                .accessibilityIdentifier("kigo.kanji")
        }
    }
}
