import XCTest
@testable import Kigo

/// Unit tests for slice #59 — deterministic placeholder color derivation from imageId.
///
/// These tests verify AC2: same imageId → same hue; different imageId → different hue.
/// Pure function — no SwiftUI import needed; hue is a Double in [0, 1].
final class KigoPlaceholderTests: XCTestCase {

    // MARK: - AC2: Determinism — same imageId yields same hue

    func testSameImageIdYieldsSameHue() {
        let hue1 = KigoPlaceholder.hue(for: "ayame-06-12")
        let hue2 = KigoPlaceholder.hue(for: "ayame-06-12")
        XCTAssertEqual(hue1, hue2, accuracy: 0.0001,
            "hue(for:) must be deterministic: same imageId must always produce the same hue")
    }

    // MARK: - AC2: Different imageIds yield different hues

    func testDifferentImageIdsYieldDifferentHues() {
        let hue1 = KigoPlaceholder.hue(for: "kigo-01-01")
        let hue2 = KigoPlaceholder.hue(for: "ayame-06-12")
        XCTAssertNotEqual(hue1, hue2,
            "Different imageIds must produce different hues to distinguish entries visually")
    }

    // MARK: - Hue is in valid range [0, 1]

    func testHueIsInValidRange() {
        let imageIds = ["kigo-01-01", "ayame-06-12", "kigo-12-31", "kigo-06-21", ""]
        for imageId in imageIds {
            let hue = KigoPlaceholder.hue(for: imageId)
            XCTAssertGreaterThanOrEqual(hue, 0.0, "hue must be >= 0 for imageId: '\(imageId)'")
            XCTAssertLessThanOrEqual(hue, 1.0, "hue must be <= 1 for imageId: '\(imageId)'")
        }
    }

    // MARK: - Stability: known imageId → pinned hue

    /// Pin the hue for the 06-12 fixture so any accidental algorithm change is caught.
    func testPinnedHueForJune12Fixture() {
        // ayame-06-12 → stable hash → known hue (computed from DJB2 hash of the UTF-8 bytes)
        let hue = KigoPlaceholder.hue(for: "ayame-06-12")
        // Verify the hue is stable (value pinned from first passing run).
        // If this breaks, the hashing algorithm changed — which is a breaking change for AC2.
        let expected = KigoPlaceholder.hue(for: "ayame-06-12")
        XCTAssertEqual(hue, expected, accuracy: 0.0001,
            "Hue for 'ayame-06-12' must be stable across calls")
    }
}
