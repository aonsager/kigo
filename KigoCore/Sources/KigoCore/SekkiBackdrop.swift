import Foundation

/// Maps a Sekki to its bundled backdrop (image pivot, ADR 0026 — supersedes 0022).
///
/// The app pivoted from per-day photography to 24 uniform, bundled, per-Sekki
/// blurred backdrops. This resolver is pure and Foundation-only (returns a `Double`
/// hue, never a SwiftUI `Color`) so it lives in the fast lane. The app layer turns
/// the asset name into a bundled `Image` and the hue into a gradient wash.
public enum SekkiBackdrop {

    /// The bundled asset name for a Sekki, by convention `"backdrop-<sekkiId>"`.
    /// The 24 Sekki ids are stable and distinct (C2 referential integrity), so the
    /// 24 asset names are distinct.
    public static func assetName(forSekkiId id: String) -> String {
        "backdrop-\(id)"
    }

    /// A deterministic hue in `[0, 1]` seeded purely by the Sekki id, used to build a
    /// per-Sekki gradient wash when the bundled backdrop asset is absent (real art is
    /// sourced out-of-band). DJB2 hash over UTF-8 bytes, normalised by `UInt32.max`.
    public static func fallbackHue(forSekkiId id: String) -> Double {
        var hash: UInt32 = 5381
        for byte in id.utf8 {
            hash = hash &* 33 &+ UInt32(byte)
        }
        return Double(hash) / Double(UInt32.max)
    }
}
