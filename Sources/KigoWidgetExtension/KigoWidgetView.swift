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
// Asagiri revamp: the word is set in bundled Shippori Mincho over the shared
// paper/warm-black canvas (Basic) or over the revealed image with a legibility
// scrim (Premium). The image is the single thing the subscription unlocks.
//
// The view is pure data-driven — no loading, no async, no resolution logic.
// All of that lives in `WidgetTimelineBuilder`.
struct KigoWidgetView: View {
    let entry: KigoWidgetEntry

    @Environment(\.widgetFamily) private var family

    /// Whether the revealed image layer should render (Premium + a resolved image).
    private var showsImage: Bool {
        entry.showsImage && entry.imageId != nil
    }

    private var kanjiSize: CGFloat {
        family == .systemSmall ? 34 : 40
    }

    var body: some View {
        ZStack {
            if showsImage, let imageId = entry.imageId {
                KigoPlaceholderView(imageId: imageId)
                // Legibility scrim so the word reads over any image.
                LinearGradient(
                    colors: [.black.opacity(0.10), .black.opacity(0.42)],
                    startPoint: .top, endPoint: .bottom
                )
            } else {
                KigoTheme.canvas
            }

            VStack(spacing: 6) {
                if let kanji = entry.kanji {
                    Text(kanji)
                        .font(KigoFont.mincho(.extrabold, size: kanjiSize, relativeTo: .largeTitle))
                        .tracking(1)
                        .foregroundStyle(showsImage ? Color.white : KigoTheme.inkKanji)
                        .shadow(color: showsImage ? .black.opacity(0.45) : KigoTheme.kanjiShadow,
                                radius: showsImage ? 8 : 2, x: 0, y: 1)
                }

                if let reading = entry.reading {
                    Text(reading)
                        .font(KigoFont.zenKaku(.regular, size: 13, relativeTo: .subheadline))
                        .tracking(4)
                        .foregroundStyle(showsImage ? Color.white.opacity(0.82) : KigoTheme.inkReading)
                }
            }
            .multilineTextAlignment(.center)
            .padding()
        }
        .containerBackground(KigoTheme.canvas, for: .widget)
    }
}
