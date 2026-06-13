import SwiftUI

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
}

// MARK: - KigoPlaceholderView

/// A full-bleed placeholder background layer for the Today screen.
///
/// Renders a deterministic gradient derived from `imageId` — same entry always
/// produces the same visual. Carries the accessibility identifier `kigo.image`
/// so UI tests can locate it as an image element.
struct KigoPlaceholderView: View {
    let imageId: String

    var body: some View {
        KigoPlaceholder.gradient(for: imageId)
            .ignoresSafeArea()
            .accessibilityIdentifier("kigo.image")
            .accessibilityLabel("Kigo background image")
            .accessibilityAddTraits(.isImage)
    }
}
