import XCTest

// MARK: - PaywallUITests

/// UI tests for slice #85 — Upgrade entry on Today presents the Paywall sheet.
///
/// Acceptance criteria verified:
/// AC1: An element with accessibilityIdentifier `paywall.entry` exists on the Today screen.
/// AC2: Tapping `paywall.entry` presents a sheet whose root container carries
///      accessibilityIdentifier `paywall.sheet`.
///
/// Both tests launch with `KIGO_FAKE_DATE=2026-06-12` and `KIGO_FAKE_ENTITLEMENT=inactive`
/// so the app lands on the Today screen with a deterministic date and a fake entitlement
/// source that reports no products owned (avoiding any real StoreKit / storekitd call —
/// see ADR 0009 and CLAUDE.md).
///
/// Screenshot evidence for AC2:
/// After the sheet appears, `XCUIScreen.main.screenshot()` is captured and attached as
/// an `XCTAttachment` with `lifetime = .keepAlways` and name `"slice-85-paywall-sheet"`.
/// Full test identifier: KigoUITests/PaywallUITests/testTappingUpgradeEntryPresentsSheet
final class PaywallUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["KIGO_FAKE_DATE"] = "2026-06-12"
        app.launchEnvironment["KIGO_FAKE_ENTITLEMENT"] = "inactive"
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - AC1: paywall.entry element is present on Today screen

    /// AC1: An element with accessibilityIdentifier `paywall.entry` must exist on
    /// the Today screen when the app is launched with KIGO_FAKE_ENTITLEMENT=inactive.
    func testUpgradeEntryExistsOnTodayScreen() {
        let entry = app.buttons["paywall.entry"]
        XCTAssertTrue(
            entry.waitForExistence(timeout: 10),
            "An element with accessibilityIdentifier 'paywall.entry' must exist on the Today screen"
        )
    }

    // MARK: - AC2: Tapping paywall.entry presents paywall.sheet

    /// AC2: Tapping the Upgrade entry must present a sheet whose root container
    /// carries accessibilityIdentifier `paywall.sheet`.
    ///
    /// Screenshot evidence: a screenshot is captured after the sheet appears and
    /// attached as XCTAttachment with name "slice-85-paywall-sheet" and lifetime .keepAlways.
    func testTappingUpgradeEntryPresentsSheet() {
        // Tap the upgrade entry button
        let entry = app.buttons["paywall.entry"]
        XCTAssertTrue(
            entry.waitForExistence(timeout: 10),
            "paywall.entry must exist before tapping"
        )
        entry.tap()

        // Assert the paywall sheet container appears.
        // Use `.descendants(matching: .any)` to find the `paywall.sheet` element
        // regardless of its XCUI element type — SwiftUI may present the root
        // container as a group, other, or propagate the identifier to leaf children
        // depending on the accessibility configuration. Searching all descendants by
        // identifier is robust to that variation while still proving the sheet appeared.
        let sheetElement = app.descendants(matching: .any)
            .matching(identifier: "paywall.sheet")
            .firstMatch
        XCTAssertTrue(
            sheetElement.waitForExistence(timeout: 10),
            "After tapping paywall.entry, a sheet with accessibilityIdentifier 'paywall.sheet' must appear"
        )

        // Screenshot evidence — captured AFTER the sheet appears
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        attachment.name = "slice-85-paywall-sheet"
        add(attachment)
    }
}
