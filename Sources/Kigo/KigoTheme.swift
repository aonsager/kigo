import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - KigoTheme

/// Design tokens for the **Asagiri** direction (朝霧, "morning mist") — the
/// high-fidelity visual language recreated from `Kigo Revamp.dc.html`.
///
/// Every colour is **appearance-adaptive**: it is built from a dynamic
/// `UIColor` provider so a single token resolves to its light or dark value
/// under the system appearance, without callers threading `colorScheme`. The
/// app follows the system appearance (`.preferredColorScheme`), so these tokens
/// give Today, the sheets and the widget one coherent palette in both modes.
///
/// Exact values are taken from the handoff's Design Tokens section.
enum KigoTheme {

    // MARK: Colour primitives

    /// An opaque colour from a 24-bit `0xRRGGBB` literal.
    static func hex(_ rgb: UInt, _ opacity: Double = 1) -> Color {
        Color(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// A colour that resolves to `light` or `dark` based on the rendering
    /// trait collection's interface style.
    static func adaptive(light: Color, dark: Color) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    // MARK: Surfaces

    /// The page / Today canvas behind the full-bleed image (also the fallback
    /// when no image is present).
    static let canvas = adaptive(light: hex(0xEDE8DF), dark: hex(0x14110D))

    /// Quiet-state frame (loading / unavailable) — slightly lighter than canvas.
    static let quietSurface = adaptive(light: hex(0xF4F0E8), dark: hex(0x16130F))

    /// Bottom-sheet / panel surface (paywall, almanac, attribution).
    static let sheetSurface = adaptive(light: hex(0xF6F2EA), dark: hex(0x1B1813))

    // MARK: Ink (foreground text)

    static let inkKanji = adaptive(light: hex(0x211D17), dark: hex(0xF4EFE6))
    static let inkReading = adaptive(light: hex(0x5E584C), dark: Color.white.opacity(0.74))
    static let inkDescription = adaptive(light: hex(0x2C271F), dark: hex(0xF0EBE1).opacity(0.88))
    static let inkKo = adaptive(light: hex(0x241F19), dark: hex(0xF4EFE6))
    static let inkSekki = adaptive(light: hex(0x6E6757), dark: Color.white.opacity(0.70))

    /// Long-form prose body inside the almanac.
    static let bodyProse = adaptive(light: hex(0x3F3930), dark: hex(0xF0EBE1).opacity(0.88))

    /// Warm-gold gloss line (sekki gloss / kō gloss). Sumi-brown in light, gold in dark.
    static let gloss = adaptive(light: hex(0x7E7768), dark: hex(0xE0B664).opacity(0.95))

    // MARK: Secondary / chrome

    static let textSecondary = adaptive(light: hex(0x857E70), dark: Color.white.opacity(0.66))
    static let textTertiary = adaptive(light: hex(0xA29B8D), dark: Color.white.opacity(0.50))
    static let hairline = adaptive(light: Color.black.opacity(0.10), dark: Color.white.opacity(0.14))

    /// Soft halo behind the focal kanji that lifts it off busy photography —
    /// a pale paper glow in light, a deep shadow in dark.
    static let kanjiShadow = adaptive(light: Color.white.opacity(0.40), dark: Color.black.opacity(0.55))

    /// Inactive ticks on the microseason year timeline.
    static let tickInactive = adaptive(light: Color.black.opacity(0.22), dark: Color.white.opacity(0.30))

    // MARK: Accent

    /// Vermilion — the chosen accent. Used for the Subscribe button, today's
    /// microseason tick, progress-bar fills, the spinner and the upgrade dot.
    static let accent = hex(0xB23A2E)

    /// A muted track behind accent gauges.
    static let accentTrack = adaptive(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.16))

    /// Premium / subscription-active green.
    static let premium = adaptive(light: hex(0x5E7A5C), dark: hex(0x86A682))

    // MARK: Season bands (春 / 夏 / 秋 / 冬), behind the 72-tick timeline

    /// The four season-tint bands, in calendar order spring → winter.
    static let seasonBands: [Color] = [
        adaptive(light: Color(red: 120/255, green: 150/255, blue: 110/255, opacity: 0.16),
                 dark: Color(red: 150/255, green: 190/255, blue: 135/255, opacity: 0.32)),
        adaptive(light: Color(red: 196/255, green: 150/255, blue: 70/255, opacity: 0.18),
                 dark: Color(red: 226/255, green: 182/255, blue: 95/255, opacity: 0.42)),
        adaptive(light: Color(red: 170/255, green: 90/255, blue: 55/255, opacity: 0.15),
                 dark: Color(red: 216/255, green: 122/255, blue: 82/255, opacity: 0.36)),
        adaptive(light: Color(red: 90/255, green: 110/255, blue: 140/255, opacity: 0.15),
                 dark: Color(red: 140/255, green: 170/255, blue: 210/255, opacity: 0.36)),
    ]

    // MARK: Legibility veil

    /// One stop of the legibility veil at the given vertical location, adapting
    /// to a paper base (light) or warm-black base (dark).
    private static func veil(_ opacity: Double, at location: Double) -> Gradient.Stop {
        .init(
            color: adaptive(
                light: Color(red: 245/255, green: 241/255, blue: 233/255, opacity: opacity),
                dark: Color(red: 15/255, green: 12/255, blue: 9/255, opacity: opacity)
            ),
            location: location
        )
    }

    /// The vertical gradient laid over the full-bleed image: denser at the top
    /// and bottom, lighter through the central text zone.
    static var legibilityVeil: LinearGradient {
        LinearGradient(
            stops: [
                veil(0.55, at: 0.0),
                veil(0.16, at: 0.30),
                veil(0.40, at: 0.62),
                veil(0.82, at: 0.88),
                veil(0.95, at: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Tint laid under the frosted material so the blur reads as paper/ink, not grey.
    static let frostedTint = adaptive(
        light: Color(red: 247/255, green: 243/255, blue: 235/255, opacity: 0.36),
        dark: Color(red: 13/255, green: 11/255, blue: 8/255, opacity: 0.46)
    )

    // MARK: Geometry

    enum Radius {
        static let sheet: CGFloat = 30
        static let infoPanel: CGFloat = 26
        static let widget: CGFloat = 22
        static let button: CGFloat = 15
        static let pill: CGFloat = 100
        static let entryCircle: CGFloat = 27
    }

    // MARK: Motion

    enum Motion {
        /// Bottom-sheet / panel slide (`cubic-bezier(.32,.72,0,1)`, ~0.55s).
        static let sheet = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.55)
        /// One-shot entrance for the Today text column.
        static let entrance = Animation.easeOut(duration: 1.0)
        static let imageReveal = Animation.easeOut(duration: 1.7)
    }
}

// MARK: - LegibilityScrim

/// The shared "paper veil + feathered frosted plate" stack that keeps text
/// legible over photography (the prototype's `gradient-veil` + radially-masked
/// `backdrop-filter: blur(7px)`). Layered between the full-bleed image and the
/// text column on Today, behind the Settings/paywall content, and reused by the
/// Premium widget.
///
/// The frosted material is radially masked so only the central text zone is
/// frosted, fading to clear photo at the edges (matching
/// `mask-image: radial-gradient(135% 50% at 50% 48%, #000 34%, transparent 76%)`).
struct LegibilityScrim: View {
    /// Blur radius of the frosted plate. The prototype uses 7px.
    var blurRadius: CGFloat = 7

    var body: some View {
        ZStack {
            KigoTheme.legibilityVeil
                .ignoresSafeArea()

            GeometryReader { proxy in
                let maxDimension = max(proxy.size.width, proxy.size.height)
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(KigoTheme.frostedTint)
                    .mask(
                        RadialGradient(
                            stops: [
                                .init(color: .black, location: 0.34),
                                .init(color: .clear, location: 0.76),
                            ],
                            center: UnitPoint(x: 0.5, y: 0.48),
                            startRadius: 0,
                            endRadius: maxDimension * 0.7
                        )
                    )
            }
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }
}
