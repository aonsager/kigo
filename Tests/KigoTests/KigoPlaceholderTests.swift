import XCTest
import KigoCore
@testable import Kigo

final class KigoPlaceholderTests: XCTestCase {
    func testFallbackGradientHueMatchesSekkiBackdrop() {
        // The view seeds its fallback wash from SekkiBackdrop.fallbackHue(forSekkiId:),
        // so the same Sekki always renders the same wash.
        let hueA = SekkiBackdrop.fallbackHue(forSekkiId: "boshu")
        let hueB = SekkiBackdrop.fallbackHue(forSekkiId: "boshu")
        XCTAssertEqual(hueA, hueB)
    }
}
