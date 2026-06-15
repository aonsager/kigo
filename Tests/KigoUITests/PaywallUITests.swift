import XCTest

// MARK: - PaywallUITests

/// UI tests for slice #85 and slice #86 — Paywall sheet presentation and offer-display.
///
/// Acceptance criteria verified:
/// AC1: An element with accessibilityIdentifier `paywall.entry` exists on the Today screen.
/// AC2: Tapping `paywall.entry` presents a sheet whose root container carries
///      accessibilityIdentifier `paywall.sheet`.
/// AC3 (slice #86): Opening the Paywall under `KIGO_FAKE_PRICE=¥300` shows
///      `paywall.price` containing "¥300" and a non-empty `paywall.duration`.
///
/// All tests launch with `KIGO_FAKE_DATE=2026-06-12` and `KIGO_FAKE_ENTITLEMENT=inactive`
/// so the app lands on the Today screen with a deterministic date and a fake entitlement
/// source that reports no products owned (avoiding any real StoreKit / storekitd call —
/// see ADR 0009 and CLAUDE.md).
///
/// Screenshot evidence for AC2:
/// After the sheet appears, `XCUIScreen.main.screenshot()` is captured and attached as
/// an `XCTAttachment` with `lifetime = .keepAlways` and name `"slice-85-paywall-sheet"`.
/// Full test identifier: KigoUITests/PaywallUITests/testTappingUpgradeEntryPresentsSheet
///
/// Screenshot evidence for AC3 (slice #86):
/// After the sheet appears with price/duration visible, a screenshot is captured and attached
/// as an `XCTAttachment` with `lifetime = .keepAlways` and name `"slice-86-paywall-offer"`.
/// Full test identifier: KigoUITests/PaywallUITests/testPaywallShowsInjectedPriceAndDuration
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

    // MARK: - AC (slice #87): paywall.benefits, paywall.buy, paywall.restore; buy is inert

    /// Slice #87: The Basic (inactive) Paywall must show:
    ///   - `paywall.benefits` with a non-empty label describing the Widget image-reveal benefit.
    ///   - `paywall.buy` — the prominent buy button (present but inert this milestone).
    ///   - `paywall.restore` — the Restore Purchases button.
    /// After tapping `paywall.buy`, the sheet must remain visible (buy is inert — no purchase
    /// flow wired yet; that is C10 / out of scope for this slice).
    ///
    /// Screenshot evidence: captured after all elements are confirmed present, attached as
    /// `slice-87-basic-paywall` with lifetime `.keepAlways`.
    /// Full test identifier: KigoUITests/PaywallUITests/testBasicPaywallShowsBenefitsBuyRestore
    func testBasicPaywallShowsBenefitsBuyRestore() {
        // Re-launch with KIGO_FAKE_PRICE set.
        app.terminate()
        app = XCUIApplication()
        app.launchEnvironment["KIGO_FAKE_DATE"] = "2026-06-12"
        app.launchEnvironment["KIGO_FAKE_ENTITLEMENT"] = "inactive"
        app.launchEnvironment["KIGO_FAKE_PRICE"] = "¥300"
        app.launch()

        // Open the paywall sheet via the upgrade entry.
        let entry = app.buttons["paywall.entry"]
        XCTAssertTrue(
            entry.waitForExistence(timeout: 10),
            "paywall.entry must exist before tapping"
        )
        entry.tap()

        // Assert the sheet container is present.
        let sheetElement = app.descendants(matching: .any)
            .matching(identifier: "paywall.sheet")
            .firstMatch
        XCTAssertTrue(
            sheetElement.waitForExistence(timeout: 10),
            "paywall.sheet must appear after tapping Upgrade"
        )

        // --- AC: paywall.benefits is present and non-empty ---
        let benefitsAny = app.descendants(matching: .any)
            .matching(identifier: "paywall.benefits")
            .firstMatch
        XCTAssertTrue(
            benefitsAny.waitForExistence(timeout: 5),
            "paywall.benefits element must exist in the paywall sheet"
        )
        XCTAssertFalse(
            benefitsAny.label.isEmpty,
            "paywall.benefits label must be non-empty; got empty string"
        )

        // --- AC: paywall.buy is present ---
        let buyAny = app.descendants(matching: .any)
            .matching(identifier: "paywall.buy")
            .firstMatch
        XCTAssertTrue(
            buyAny.waitForExistence(timeout: 5),
            "paywall.buy element must exist in the paywall sheet"
        )

        // --- AC: paywall.restore is present ---
        let restoreAny = app.descendants(matching: .any)
            .matching(identifier: "paywall.restore")
            .firstMatch
        XCTAssertTrue(
            restoreAny.waitForExistence(timeout: 5),
            "paywall.restore element must exist in the paywall sheet"
        )

        // Screenshot evidence — captured BEFORE the inertness assertion (sheet still open).
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        attachment.name = "slice-87-basic-paywall"
        add(attachment)

        // --- AC: buy is inert — tapping buy must NOT dismiss the sheet ---
        // Re-fetch buy element after screenshot so we have a fresh reference.
        let buyButton = app.descendants(matching: .any)
            .matching(identifier: "paywall.buy")
            .firstMatch
        XCTAssertTrue(
            buyButton.exists,
            "paywall.buy must still exist before inertness tap"
        )
        buyButton.tap()

        // Wait briefly for any animation that a dismissal might trigger, then assert.
        let sheetStillPresent = app.descendants(matching: .any)
            .matching(identifier: "paywall.sheet")
            .firstMatch
        XCTAssertTrue(
            sheetStillPresent.waitForExistence(timeout: 3),
            "paywall.sheet must remain visible after tapping paywall.buy (buy is inert this milestone)"
        )
        let buyStillPresent = app.descendants(matching: .any)
            .matching(identifier: "paywall.buy")
            .firstMatch
        XCTAssertTrue(
            buyStillPresent.exists,
            "paywall.buy must remain present after tapping (buy is inert this milestone)"
        )
    }

    // MARK: - AC3 (slice #86): paywall.price and paywall.duration elements

    /// AC3: Opening the Paywall with `KIGO_FAKE_PRICE=¥300` must show an element
    /// `paywall.price` whose label contains "¥300" and an element `paywall.duration`
    /// with a non-empty label.
    ///
    /// Screenshot evidence: captured after price/duration appear, attached as
    /// `slice-86-paywall-offer` with lifetime `.keepAlways`.
    /// Full test identifier: KigoUITests/PaywallUITests/testPaywallShowsInjectedPriceAndDuration
    func testPaywallShowsInjectedPriceAndDuration() {
        // Re-launch with KIGO_FAKE_PRICE set (setUp already set date + entitlement).
        // We need to terminate the app from setUp and relaunch with the extra env var.
        app.terminate()
        app = XCUIApplication()
        app.launchEnvironment["KIGO_FAKE_DATE"] = "2026-06-12"
        app.launchEnvironment["KIGO_FAKE_ENTITLEMENT"] = "inactive"
        app.launchEnvironment["KIGO_FAKE_PRICE"] = "¥300"
        app.launch()

        // Tap the Upgrade entry to open the paywall sheet.
        let entry = app.buttons["paywall.entry"]
        XCTAssertTrue(
            entry.waitForExistence(timeout: 10),
            "paywall.entry must exist before tapping"
        )
        entry.tap()

        // Assert paywall.sheet is visible.
        let sheetElement = app.descendants(matching: .any)
            .matching(identifier: "paywall.sheet")
            .firstMatch
        XCTAssertTrue(
            sheetElement.waitForExistence(timeout: 10),
            "paywall.sheet must appear after tapping Upgrade"
        )

        // Assert paywall.price element exists and contains the injected price string.
        // Try both staticTexts (Text views) and any descendant to be resilient to
        // SwiftUI's accessibility element type mapping on iOS 26.
        let priceStatic = app.staticTexts["paywall.price"]
        let priceAny = app.descendants(matching: .any).matching(identifier: "paywall.price").firstMatch
        let priceFound = priceStatic.waitForExistence(timeout: 5) || priceAny.waitForExistence(timeout: 5)
        XCTAssertTrue(
            priceFound,
            "paywall.price element must exist in the paywall sheet"
        )
        let priceLabel = priceStatic.exists ? priceStatic.label : priceAny.label
        XCTAssertTrue(
            priceLabel.contains("¥300"),
            "paywall.price label must contain the injected price '¥300'; got: '\(priceLabel)'"
        )

        // Assert paywall.duration element exists with a non-empty label.
        let durationStatic = app.staticTexts["paywall.duration"]
        let durationAny = app.descendants(matching: .any).matching(identifier: "paywall.duration").firstMatch
        let durationFound = durationStatic.waitForExistence(timeout: 5) || durationAny.waitForExistence(timeout: 5)
        XCTAssertTrue(
            durationFound,
            "paywall.duration element must exist in the paywall sheet"
        )
        let durationLabel = durationStatic.exists ? durationStatic.label : durationAny.label
        XCTAssertFalse(
            durationLabel.isEmpty,
            "paywall.duration label must be non-empty"
        )

        // Screenshot evidence — slice-86-paywall-offer
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        attachment.name = "slice-86-paywall-offer"
        add(attachment)
    }
}
