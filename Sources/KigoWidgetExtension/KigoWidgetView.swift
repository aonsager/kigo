import SwiftUI
import WidgetKit

// MARK: - KigoWidgetView
//
// Slice #73: Widget view for systemSmall and systemMedium families.
//
// Renders today's Kigo kanji and reading in all cases. When `entry.showsImage`
// is true (active subscription entitlement), a full-bleed deterministic
// placeholder image is shown behind the text — the same `KigoPlaceholderView`
// used by the app's Today screen (ADR 0001 / J2). When `showsImage` is false,
// only the kanji and reading are shown.
//
// Layout is intentionally restrained:
//   - Kanji at `.largeTitle` weight (prominent, single word)
//   - Reading at `.title2` weight below
//   - Text layer centred and padded against the gradient background
//
// The view is pure data-driven — no loading, no async, no resolution logic.
// All of that lives in `WidgetTimelineBuilder`.
//
// Extracted into its own file so it can be compiled into `KigoWidgetTests`
// for direct unit verification (the @main entry point in KigoWidget.swift
// is excluded from the test target).
struct KigoWidgetView: View {
    let entry: KigoWidgetEntry

    var body: some View {
        ZStack {
            if entry.showsImage, let imageId = entry.imageId {
                // Full-bleed deterministic gradient placeholder — same visual
                // as the app's Today screen for visual consistency.
                KigoPlaceholderView(imageId: imageId)
            } else {
                // Plain background when no image entitlement.
                Color(.systemBackground)
                    .ignoresSafeArea()
            }

            VStack(spacing: 6) {
                if let kanji = entry.kanji {
                    Text(kanji)
                        .font(.largeTitle)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.center)
                }

                if let reading = entry.reading {
                    Text(reading)
                        .font(.title2)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
        }
        .containerBackground(.background, for: .widget)
    }
}
