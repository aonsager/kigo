import KigoCore
import SwiftUI
import WidgetKit

// MARK: - KigoWidgetView
//
// Slice #73: Widget view for systemSmall and systemMedium families.
//
// Renders today's Kigo kanji and reading over the per-Sekki backdrop — the
// same `KigoPlaceholderView` used by the app's Today screen. Since ADR 0019
// the widget is ungated (unchanged intent): the backdrop always renders,
// regardless of entitlement state.
//
// Image pivot (Task 4): the backdrop is keyed on `entry.backdropAssetName`/
// `entry.fallbackHue`, resolved by `WidgetTimelineBuilder` from the resolved
// day's Sekki (`SekkiBackdrop`) — no more `imageId`/`showsImage` gating.
//
// Asagiri revamp: the word is set in bundled Shippori Mincho over the
// revealed backdrop with a legibility scrim.
//
// The view is pure data-driven — no loading, no async, no resolution logic.
// All of that lives in `WidgetTimelineBuilder`.
struct KigoWidgetView: View {
    let entry: KigoWidgetEntry

    @Environment(\.widgetFamily) private var family

    private var kanjiSize: CGFloat {
        family == .systemSmall ? 34 : 40
    }

    var body: some View {
        ZStack {
            KigoPlaceholderView(
                backdropAssetName: entry.backdropAssetName,
                fallbackHue: entry.fallbackHue
            )
            // Legibility scrim so the word reads over any backdrop.
            LinearGradient(
                colors: [.black.opacity(0.10), .black.opacity(0.42)],
                startPoint: .top, endPoint: .bottom
            )

            VStack(spacing: 6) {
                if let kanji = entry.kanji {
                    Text(kanji)
                        .font(KigoFont.mincho(.extrabold, size: kanjiSize, relativeTo: .largeTitle))
                        .tracking(1)
                        .foregroundStyle(Color.white)
                        .shadow(color: .black.opacity(0.45), radius: 8, x: 0, y: 1)
                }

                if let reading = entry.reading {
                    Text(reading)
                        .font(KigoFont.zenKaku(.regular, size: 13, relativeTo: .subheadline))
                        .tracking(4)
                        .foregroundStyle(Color.white.opacity(0.82))
                }
            }
            .multilineTextAlignment(.center)
            .padding()
        }
        .containerBackground(KigoTheme.canvas, for: .widget)
    }
}
