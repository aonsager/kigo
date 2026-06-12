import XCTest
@testable import Kigo

final class SmokeTests: XCTestCase {

    /// Asserts the *built* app's bundle identifier matches the canonical value from
    /// GOAL.md / ADR 0002. `AppInfo.bundleIdentifier` reads `Bundle.main` at runtime,
    /// so this fails if `project.yml`'s `PRODUCT_BUNDLE_IDENTIFIER` is misconfigured —
    /// it is an assertion about the actual built artifact, not a self-comparison.
    func testBuiltBundleIdentifierIsCanonical() throws {
        XCTAssertEqual(
            AppInfo.bundleIdentifier,
            "com.tomeitotameigo.kigo",
            "The built app's bundle identifier must match the canonical value from GOAL.md"
        )
    }

    /// Asserts the built app exposes the expected display name from its Info.plist.
    func testBuiltDisplayNameIsKigo() throws {
        XCTAssertEqual(
            AppInfo.displayName,
            "Kigo",
            "The built app's display name must come from the Info.plist as 'Kigo'"
        )
    }
}
