import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - KigoPlaceholder

/// Deterministic placeholder visual derived from a Kigo entry's `imageId`.
///
/// Slice #59: No real image assets exist (ADR 0001 / J2). This type provides a
/// stable hue-shifted gradient background seeded purely by the `imageId` string —
/// same imageId always yields the same gradient, different imageIds yield
/// visually distinct gradients. No randomness, no Date-based seeding.
///
/// The hue derivation is a pure function (testable without SwiftUI) exposed as
/// `KigoPlaceholder.hue(for:)`. The SwiftUI view `KigoPlaceholderView` wraps it
/// into a full-bleed background layer.
public enum KigoPlaceholder {

    // MARK: - Deterministic hue derivation

    /// Returns a hue value in [0, 1] deterministically derived from `imageId`.
    ///
    /// Uses a DJB2-style hash over the UTF-8 bytes of `imageId`. The result is
    /// normalised into [0, 1] by dividing by `UInt32.max`. This is a pure function:
    /// given the same input, it always returns the same output.
    ///
    /// - Parameter imageId: The `imageId` string from a `DailyMapEntry`.
    /// - Returns: A hue value in [0, 1].
    public static func hue(for imageId: String) -> Double {
        var hash: UInt32 = 5381
        for byte in imageId.utf8 {
            // DJB2: hash = hash * 33 XOR byte  (wrapping to avoid overflow trap)
            hash = hash &* 33 &+ UInt32(byte)
        }
        return Double(hash) / Double(UInt32.max)
    }

    // MARK: - Gradient derivation

    /// Returns a two-stop `LinearGradient` for the given `imageId`.
    ///
    /// The primary colour is derived from the hue; the secondary colour is the
    /// primary hue shifted by +0.08 (a narrow analogous shift). Saturation and
    /// brightness are kept tasteful (low saturation, high brightness) so text
    /// laid on top remains legible.
    static func gradient(for imageId: String) -> LinearGradient {
        let primaryHue = hue(for: imageId)
        let secondaryHue = (primaryHue + 0.08).truncatingRemainder(dividingBy: 1.0)

        let primary = Color(hue: primaryHue, saturation: 0.25, brightness: 0.92)
        let secondary = Color(hue: secondaryHue, saturation: 0.30, brightness: 0.82)

        return LinearGradient(
            colors: [primary, secondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Bundled background photo (Asagiri revamp #158)

    /// The base name of the bundled full-bleed background photo.
    public static let backgroundImageName = "tsuyu"

    /// Loads the bundled `tsuyu.jpg` background photo, or `nil` if it is missing.
    ///
    /// `UIImage(named:)` does NOT reliably resolve a *loose* `.jpg` sitting at the
    /// bundle root (it primarily searches asset catalogs), so we resolve the file
    /// URL explicitly via `Bundle.main` — which is the app bundle when running in
    /// the app or hosted unit tests, and the appex bundle inside the widget, both
    /// of which carry `tsuyu.jpg`. Falls back to `UIImage(named:)` just in case.
    public static func backgroundImage() -> UIImage? {
        if let url = Bundle.main.url(forResource: backgroundImageName, withExtension: "jpg"),
           let image = UIImage(contentsOfFile: url.path) {
            return image
        }
        return UIImage(named: backgroundImageName)
    }
}

// MARK: - KigoPlaceholderView

/// A full-bleed background layer for the Today screen.
///
/// Asagiri revamp (#158): renders the bundled photo `tsuyu.jpg` full-bleed.
/// The image is looked up loose-file in the bundle via `UIImage(named:)`. If it
/// fails to load (e.g. the resource is missing), the view falls back to the
/// deterministic `KigoPlaceholder.gradient(for:)` so the screen is never blank.
///
/// Carries the accessibility identifier `kigo.image` so UI tests can locate it
/// as a full-bleed image element.
struct KigoPlaceholderView: View {
    let imageId: String

    var body: some View {
        background
            .ignoresSafeArea()
            .accessibilityIdentifier("kigo.image")
            .accessibilityLabel("Kigo background image")
            .accessibilityAddTraits(.isImage)
    }

    @ViewBuilder
    private var background: some View {
        if let uiImage = KigoPlaceholder.backgroundImage() {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .clipped()
        } else {
            // Fallback so the screen is never blank if the photo fails to load.
            KigoPlaceholder.gradient(for: imageId)
        }
    }
}
