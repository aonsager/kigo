import KigoCore
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - KigoPlaceholder

/// The full-bleed seasonal backdrop, keyed by the current Sekki (image pivot).
///
/// The app shows one bundled, heavily-blurred, palette-matched backdrop per Sekki
/// (24 total), named `backdrop-<sekkiId>`. Until the real art is sourced out-of-band,
/// a deterministic per-Sekki gradient wash stands in, so the screen is never blank.
public enum KigoPlaceholder {

    /// A two-stop gradient wash for a given fallback hue (from `SekkiBackdrop.fallbackHue`).
    /// Low saturation / high brightness keeps overlaid sumi-ink text legible.
    static func gradient(forHue primaryHue: Double) -> LinearGradient {
        let secondaryHue = (primaryHue + 0.08).truncatingRemainder(dividingBy: 1.0)
        let primary = Color(hue: primaryHue, saturation: 0.25, brightness: 0.92)
        let secondary = Color(hue: secondaryHue, saturation: 0.30, brightness: 0.82)
        return LinearGradient(colors: [primary, secondary],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Loads a bundled backdrop by asset name (`backdrop-<sekkiId>`), or `nil` if absent.
    /// Resolves both a loose `.jpg` at the bundle root and an asset-catalog entry, so it
    /// works in the app, hosted tests, and the widget appex. Returns `nil` when the art has
    /// not yet been added — callers fall back to `gradient(forHue:)`.
    public static func backdropImage(named name: String) -> UIImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: "jpg"),
           let image = UIImage(contentsOfFile: url.path) {
            return image
        }
        return UIImage(named: name)
    }
}

// MARK: - KigoPlaceholderView

/// A full-bleed seasonal backdrop layer, shared by the Today screen and the Widget.
///
/// Renders the bundled `backdropAssetName` if present, else a deterministic per-Sekki
/// gradient wash from `fallbackHue`. Carries the `kigo.image` accessibility identifier
/// so UI tests locate it as the full-bleed image element (unchanged contract).
struct KigoPlaceholderView: View {
    let backdropAssetName: String
    let fallbackHue: Double

    /// VoiceOver label for the decorative backdrop. Injected as a plain string because this
    /// view is shared with the widget extension, which does not compile `LanguagePreference`.
    var accessibilityLabelText: String = "季語の背景画像"

    var body: some View {
        GeometryReader { geo in
            ZStack {
                background
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .accessibilityHidden(true)

                // ADR-0013 sentinel: a full-screen clear leaf carries `kigo.image` with a
                // frame that exactly matches the window (scaledToFill overflow would report
                // a too-wide frame and break TodayLayoutUITests.testImageFullBleed).
                Color.clear
                    .accessibilityIdentifier("kigo.image")
                    .accessibilityLabel(accessibilityLabelText)
                    .accessibilityAddTraits(.isImage)
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var background: some View {
        if let uiImage = KigoPlaceholder.backdropImage(named: backdropAssetName) {
            Image(uiImage: uiImage).resizable().scaledToFill()
        } else {
            KigoPlaceholder.gradient(forHue: fallbackHue)
        }
    }
}
