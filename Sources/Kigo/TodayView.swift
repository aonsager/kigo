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
/// Extended in slice #59 to add a full-bleed deterministic placeholder image behind
/// the text content (`kigo.image`). The placeholder is derived from the entry's
/// `imageId` — same imageId always renders the same gradient, different imageIds
/// render distinct gradients. No real image assets are loaded (ADR 0001 / J2).
///
/// Extended in slice #122 to accept `AlmanacPositions` and render the
/// `microseason.timeline` tappable affordance beneath the Microseason section.
///
/// Extended in slice #123 to wire the tap action: tapping `microseason.timeline`
/// sets `isAlmanacPresented = true` and presents `AlmanacSheetView` as a `.sheet`.
/// Swiping down or tapping the backdrop sets `isAlmanacPresented = false`.
///
/// Extended in slice #128 to add an `info.entry` button (top-left, x < width/2, y < height/3)
/// that presents `AttributionPanelView` as a `.sheet` for image attribution info.
///
/// Extended in slice #132 to consolidate the two-Bool sheet pattern into a single
/// `ActiveSheet` enum-driven `.sheet(item:)` modifier, eliminating the two stacked
/// `.sheet` modifiers and replacing them with one.
struct TodayView: View {
    let resolvedDay: ResolvedDay
    let almanacPositions: AlmanacPositions

    /// Identifies which sheet is currently active. Conforms to `Identifiable` so
    /// it can drive the single `.sheet(item:)` modifier.
    private enum ActiveSheet: Identifiable {
        case almanac
        case attribution

        var id: Self { self }
    }

    @State private var activeSheet: ActiveSheet?

    var body: some View {
        ZStack {
            // Full-bleed placeholder image layer — behind the text content.
            // Derived deterministically from imageId (slice #59, AC1–AC2).
            KigoPlaceholderView(imageId: resolvedDay.kigoEntry.imageId)

            // Text content layer — rendered on top of the placeholder.
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

                // Microseason timeline affordance (slice #122 / #123).
                // Tapping presents AlmanacSheetView as a modal sheet.
                Button(action: {
                    activeSheet = .almanac
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                        Text("\(almanacPositions.koYearPosition) / \(almanacPositions.koYearTotal)")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .accessibilityIdentifier("microseason.timeline")
                .accessibilityLabel("Microseason timeline: Kō \(almanacPositions.koYearPosition) of \(almanacPositions.koYearTotal)")
            }

            // Info entry button — top-left placement (x < width/2, y < height/3).
            // Tapping presents AttributionPanelView as a modal sheet.
            VStack {
                HStack {
                    Button(action: {
                        activeSheet = .attribution
                    }) {
                        Image(systemName: "info.circle")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityIdentifier("info.entry")
                    .accessibilityLabel("Image attribution")
                    .padding(.leading, 16)
                    .padding(.top, 16)

                    Spacer()
                }
                Spacer()
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .almanac:
                AlmanacSheetView(almanacPositions: almanacPositions, ko: resolvedDay.ko)
            case .attribution:
                AttributionPanelView(attribution: resolvedDay.kigoEntry.attribution)
            }
        }
    }
}
