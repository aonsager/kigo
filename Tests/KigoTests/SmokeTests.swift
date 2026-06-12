import XCTest
@testable import Kigo

final class SmokeTests: XCTestCase {

    /// Verifies the canonical bundle identifier constant matches the value declared in GOAL.md.
    /// This is a real assertion about app metadata — not a tautology.
    func testCanonicalBundleIdentifier() throws {
        XCTAssertEqual(
            AppInfo.bundleIdentifier,
            "com.tomeitotameigo.kigo",
            "Bundle identifier must match the canonical value from ADR 0002 / GOAL.md"
        )
    }

    /// Verifies that AppInfo exposes a non-empty display name.
    func testAppDisplayNameIsNonEmpty() throws {
        XCTAssertFalse(
            AppInfo.displayName.isEmpty,
            "AppInfo.displayName must be a non-empty string"
        )
    }
}
