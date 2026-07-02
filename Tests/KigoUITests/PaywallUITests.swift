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

        // Open the purchase sheet via the Basic-tier meaning.upsell band (PRD #189:
        // the marketing/buy flow moved out of Settings into this dedicated sheet).
        let entry = app.buttons["meaning.upsell"]
        XCTAssertTrue(
            entry.waitForExistence(timeout: 10),
            "meaning.upsell must exist before tapping"
        )
        entry.tap()

        // Assert the sheet container is present.
        let sheetElement = app.descendants(matching: .any)
            .matching(identifier: "paywall.sheet")
            .firstMatch
        XCTAssertTrue(
            sheetElement.waitForExistence(timeout: 10),
            "paywall.sheet must appear after tapping the upsell"
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

        // --- AC: tapping buy without KIGO_FAKE_PURCHASER set must not crash or dismiss the sheet ---
        // With no KIGO_FAKE_PURCHASER, the production StoreKitSubscriptionPurchaser is used;
        // Product.products(for:) will fail (no StoreKit config under xcodebuild) and buy()
        // swallows the error — isActive stays false, sheet stays open, no crash.
        // Re-fetch buy element after screenshot so we have a fresh reference.
        let buyButton = app.descendants(matching: .any)
            .matching(identifier: "paywall.buy")
            .firstMatch
        XCTAssertTrue(
            buyButton.exists,
            "paywall.buy must still exist before tapping"
        )
        buyButton.tap()

        // Wait briefly for any animation that a dismissal might trigger, then assert.
        let sheetStillPresent = app.descendants(matching: .any)
            .matching(identifier: "paywall.sheet")
            .firstMatch
        XCTAssertTrue(
            sheetStillPresent.waitForExistence(timeout: 3),
            "paywall.sheet must remain visible after tapping paywall.buy with no fake purchaser (error swallowed)"
        )
        let buyStillPresent = app.descendants(matching: .any)
            .matching(identifier: "paywall.buy")
            .firstMatch
        XCTAssertTrue(
            buyStillPresent.exists,
            "paywall.buy must remain present (isActive stays false when purchaser fails silently)"
        )
    }

    // MARK: - AC (slice #88): paywall.terms and paywall.privacy link elements

    /// Slice #88: The Basic (inactive) Paywall must show link elements for
    /// Terms of Use (`paywall.terms`) and Privacy Policy (`paywall.privacy`).
    ///
    /// Screenshot evidence: captured after both elements are confirmed present,
    /// attached as `paywall-legal-links` with lifetime `.keepAlways`.
    /// Full test identifier: KigoUITests/PaywallUITests/testBasicPaywallShowsLegalLinks
    func testBasicPaywallShowsLegalLinks() {
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

        // --- AC: paywall.terms link element is present ---
        let termsElement = app.descendants(matching: .any)
            .matching(identifier: "paywall.terms")
            .firstMatch
        XCTAssertTrue(
            termsElement.waitForExistence(timeout: 5),
            "paywall.terms element must exist in the Basic paywall sheet"
        )

        // --- AC: paywall.privacy link element is present ---
        let privacyElement = app.descendants(matching: .any)
            .matching(identifier: "paywall.privacy")
            .firstMatch
        XCTAssertTrue(
            privacyElement.waitForExistence(timeout: 5),
            "paywall.privacy element must exist in the Basic paywall sheet"
        )

        // Screenshot evidence — captured after both link elements confirmed present.
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        attachment.name = "paywall-legal-links"
        add(attachment)
    }

    // MARK: - Slice #89: Premium (active) Paywall shows manage surface and hides buy button

    /// Slice #89: When `KIGO_FAKE_ENTITLEMENT=active`, the Paywall sheet must show an element
    /// `paywall.manage` and must NOT show `paywall.buy`.
    ///
    /// Acceptance criteria:
    ///   AC1: `paywall.manage` is present.
    ///   AC2: `paywall.buy` is absent.
    ///
    /// Screenshot evidence: captured after `paywall.manage` is confirmed, attached as
    /// `premium-paywall-manage` with lifetime `.keepAlways`.
    /// Full test identifier: KigoUITests/PaywallUITests/testPremiumPaywallShowsManage
    func testPremiumPaywallShowsManage() {
        // Re-launch with active entitlement.
        app.terminate()
        app = XCUIApplication()
        app.launchEnvironment["KIGO_FAKE_DATE"] = "2026-06-12"
        app.launchEnvironment["KIGO_FAKE_ENTITLEMENT"] = "active"
        app.launchEnvironment["KIGO_FAKE_PRICE"] = "¥300"
        app.launch()

        // Open the paywall sheet via the upgrade entry.
        // Note: paywall.entry may not appear in the active case — the sheet may need to be
        // triggered by an alternate path, but the existing architecture still shows the
        // entry button regardless; it's just the paywall content that changes.
        let entry = app.descendants(matching: .any)
            .matching(identifier: "paywall.entry")
            .firstMatch
        XCTAssertTrue(
            entry.waitForExistence(timeout: 10),
            "paywall.entry must exist to open the paywall sheet"
        )
        entry.tap()

        // Assert the sheet container is present.
        let sheetElement = app.descendants(matching: .any)
            .matching(identifier: "paywall.sheet")
            .firstMatch
        XCTAssertTrue(
            sheetElement.waitForExistence(timeout: 10),
            "paywall.sheet must appear after tapping paywall.entry"
        )

        // AC1: paywall.manage must be present
        let manageElement = app.descendants(matching: .any)
            .matching(identifier: "paywall.manage")
            .firstMatch
        XCTAssertTrue(
            manageElement.waitForExistence(timeout: 5),
            "paywall.manage element must exist when KIGO_FAKE_ENTITLEMENT=active"
        )

        // Screenshot evidence — captured AFTER paywall.manage confirmed present.
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        attachment.name = "premium-paywall-manage"
        add(attachment)

        // AC2: paywall.buy must NOT be present
        let buyElement = app.descendants(matching: .any)
            .matching(identifier: "paywall.buy")
            .firstMatch
        XCTAssertFalse(
            buyElement.exists,
            "paywall.buy must NOT exist when KIGO_FAKE_ENTITLEMENT=active"
        )
    }

    /// Slice #89 regression: When `KIGO_FAKE_ENTITLEMENT=inactive`, the Paywall sheet
    /// must still show `paywall.buy` and must NOT show `paywall.manage`.
    func testBasicPaywallDoesNotShowManage() {
        // setUp already launches with KIGO_FAKE_ENTITLEMENT=inactive.
        // Open the purchase sheet via the Basic-tier meaning.upsell band (PRD #189).
        let entry = app.buttons["meaning.upsell"]
        XCTAssertTrue(
            entry.waitForExistence(timeout: 10),
            "meaning.upsell must exist"
        )
        entry.tap()

        let sheetElement = app.descendants(matching: .any)
            .matching(identifier: "paywall.sheet")
            .firstMatch
        XCTAssertTrue(
            sheetElement.waitForExistence(timeout: 10),
            "paywall.sheet must appear"
        )

        // paywall.buy must be present
        let buyElement = app.descendants(matching: .any)
            .matching(identifier: "paywall.buy")
            .firstMatch
        XCTAssertTrue(
            buyElement.waitForExistence(timeout: 5),
            "paywall.buy must exist when KIGO_FAKE_ENTITLEMENT=inactive"
        )

        // paywall.manage must NOT be present
        let manageElement = app.descendants(matching: .any)
            .matching(identifier: "paywall.manage")
            .firstMatch
        XCTAssertFalse(
            manageElement.exists,
            "paywall.manage must NOT exist when KIGO_FAKE_ENTITLEMENT=inactive"
        )
    }

    // MARK: - PRD #189: purchase is separated from Settings

    /// The Settings sheet (opened by the gear, `paywall.entry`) must NOT contain the
    /// buy flow — `paywall.buy` lives only in the dedicated purchase sheet reached from
    /// `meaning.upsell`. Settings still exposes `paywall.sheet` + `paywall.restore`.
    func testSettingsSheetHasNoBuyButton() {
        // setUp launches with KIGO_FAKE_ENTITLEMENT=inactive.
        let gear = app.buttons["paywall.entry"]
        XCTAssertTrue(gear.waitForExistence(timeout: 10), "paywall.entry (gear) must exist")
        gear.tap()

        let sheetElement = app.descendants(matching: .any)
            .matching(identifier: "paywall.sheet")
            .firstMatch
        XCTAssertTrue(
            sheetElement.waitForExistence(timeout: 10),
            "paywall.sheet must appear after tapping the gear"
        )

        // Restore must be reachable from Settings for every user (Apple requirement).
        let restore = app.descendants(matching: .any)
            .matching(identifier: "paywall.restore")
            .firstMatch
        XCTAssertTrue(
            restore.waitForExistence(timeout: 5),
            "paywall.restore must exist in the Settings sheet"
        )

        // But the buy flow must NOT be here — it lives in the purchase sheet.
        let buyElement = app.descendants(matching: .any)
            .matching(identifier: "paywall.buy")
            .firstMatch
        XCTAssertFalse(
            buyElement.exists,
            "paywall.buy must NOT appear in the Settings sheet (PRD #189: purchase is separate)"
        )
    }

    // MARK: - AC (slice #117): Wire Subscribe button → paywall.manage appears after simulated buy

    /// Slice #117: With `KIGO_FAKE_PURCHASER=succeed`, tapping `paywall.buy` must cause
    /// the model to call through the injected fake purchaser (which flips the mutable
    /// entitlement source to report the widget product as owned), triggering a
    /// `refreshEntitlement()` that sets `isActive = true` — causing `paywall.manage` to
    /// appear and `paywall.buy` to disappear.
    ///
    /// Acceptance criteria verified:
    ///   AC1: `paywall.manage` appears within the timeout after tapping `paywall.buy`.
    ///   AC2: `paywall.buy` is no longer present after `paywall.manage` appears.
    ///
    /// Screenshot evidence: captured after `paywall.manage` is confirmed, attached as
    /// `slice-c10-buy-wiring` with lifetime `.keepAlways`.
    /// Full test identifier: KigoUITests/PaywallUITests/testWireSubscribeButtonShowsManageSurface
    func testWireSubscribeButtonShowsManageSurface() {
        // Re-launch with the fake purchaser env var set.
        app.terminate()
        app = XCUIApplication()
        app.launchEnvironment["KIGO_FAKE_DATE"] = "2026-06-12"
        app.launchEnvironment["KIGO_FAKE_ENTITLEMENT"] = "inactive"
        app.launchEnvironment["KIGO_FAKE_PRICE"] = "¥300"
        app.launchEnvironment["KIGO_FAKE_PURCHASER"] = "succeed"
        app.launch()

        // Open the purchase sheet via the Basic-tier meaning.upsell band (PRD #189:
        // the buy flow lives in the dedicated purchase sheet, not Settings).
        let entry = app.buttons["meaning.upsell"]
        XCTAssertTrue(
            entry.waitForExistence(timeout: 10),
            "meaning.upsell must exist to open the purchase sheet"
        )
        entry.tap()

        // Assert the sheet container is present.
        let sheetElement = app.descendants(matching: .any)
            .matching(identifier: "paywall.sheet")
            .firstMatch
        XCTAssertTrue(
            sheetElement.waitForExistence(timeout: 10),
            "paywall.sheet must appear after tapping the upsell"
        )

        // Assert paywall.buy is present before tapping.
        let buyButton = app.descendants(matching: .any)
            .matching(identifier: "paywall.buy")
            .firstMatch
        XCTAssertTrue(
            buyButton.waitForExistence(timeout: 5),
            "paywall.buy must exist before tapping (inactive state)"
        )

        // Tap the Subscribe button — wired to Task { await model.buy() }.
        buyButton.tap()

        // AC1: paywall.manage must appear after the simulated purchase completes.
        // The fake purchaser flips the mutable source synchronously; the async
        // chain (purchase → refreshEntitlement → isEntitlementActive → isActive)
        // must resolve before the timeout.
        let manageElement = app.descendants(matching: .any)
            .matching(identifier: "paywall.manage")
            .firstMatch
        XCTAssertTrue(
            manageElement.waitForExistence(timeout: 10),
            "paywall.manage must appear after tapping paywall.buy with KIGO_FAKE_PURCHASER=succeed"
        )

        // Screenshot evidence — captured AFTER paywall.manage appears.
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        attachment.name = "slice-c10-buy-wiring"
        add(attachment)

        // AC2: paywall.buy must no longer be present once paywall.manage appears.
        let buyGone = app.descendants(matching: .any)
            .matching(identifier: "paywall.buy")
            .firstMatch
        XCTAssertFalse(
            buyGone.exists,
            "paywall.buy must be absent after paywall.manage appears (isActive = true)"
        )
    }

    // MARK: - Slice #195: paywall.benefits copy describes the understanding layer, not the widget image

    /// Slice #195 (PRD #189): The `paywall.benefits` element must read as the
    /// *understanding-layer* offering, not the old widget-image reveal. This closes the
    /// gap that no test machine-checked the literal text content — prior tests only
    /// asserted the identifier's presence and non-emptiness.
    ///
    /// Acceptance criteria verified:
    ///   AC (a): the label MUST NOT contain stale widget-image language (the word "widget").
    ///   AC (b): the label MUST contain understanding-layer language describing the offering
    ///           (a reference to meaning, kigo, or microseason).
    ///
    /// Launched under the real app path with `KIGO_FAKE_ENTITLEMENT=inactive` and the
    /// purchase sheet opened from the Basic-tier `meaning.upsell` band (PRD #189).
    ///
    /// Screenshot evidence: captured after the benefits copy is read, attached as
    /// `slice-195-paywall-benefits-copy` with lifetime `.keepAlways`.
    /// Full test identifier: KigoUITests/PaywallUITests/testPaywallBenefitsCopyDescribesUnderstandingLayer
    func testPaywallBenefitsCopyDescribesUnderstandingLayer() {
        // setUp already launches with KIGO_FAKE_ENTITLEMENT=inactive.
        // Open the purchase sheet via the Basic-tier meaning.upsell band (PRD #189).
        let entry = app.buttons["meaning.upsell"]
        XCTAssertTrue(
            entry.waitForExistence(timeout: 10),
            "meaning.upsell must exist before tapping"
        )
        entry.tap()

        // Assert the sheet container is present.
        let sheetElement = app.descendants(matching: .any)
            .matching(identifier: "paywall.sheet")
            .firstMatch
        XCTAssertTrue(
            sheetElement.waitForExistence(timeout: 10),
            "paywall.sheet must appear after tapping the upsell"
        )

        // Read the ACTUAL label/text content of paywall.benefits (not merely its presence).
        let benefits = app.descendants(matching: .any)
            .matching(identifier: "paywall.benefits")
            .firstMatch
        XCTAssertTrue(
            benefits.waitForExistence(timeout: 5),
            "paywall.benefits element must exist in the paywall sheet"
        )
        let copy = benefits.label
        XCTAssertFalse(
            copy.isEmpty,
            "paywall.benefits label must be non-empty; got empty string"
        )

        // Screenshot evidence — captured with the benefits copy visible in the sheet.
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        attachment.name = "slice-195-paywall-benefits-copy"
        add(attachment)

        // AC (a): must NOT contain stale widget-image language.
        let lowered = copy.lowercased()
        XCTAssertFalse(
            lowered.contains("widget"),
            "paywall.benefits copy must not contain stale widget-image language; got: '\(copy)'"
        )

        // AC (b): must contain understanding-layer language describing the offering.
        let understandingTerms = ["meaning", "kigo", "microseason"]
        XCTAssertTrue(
            understandingTerms.contains(where: { lowered.contains($0) }),
            "paywall.benefits copy must describe the understanding-layer offering "
                + "(reference meaning, kigo, or microseason); got: '\(copy)'"
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

        // Open the purchase sheet via the Basic-tier meaning.upsell band (PRD #189:
        // price/offer live in the dedicated purchase sheet, not Settings).
        let entry = app.buttons["meaning.upsell"]
        XCTAssertTrue(
            entry.waitForExistence(timeout: 10),
            "meaning.upsell must exist before tapping"
        )
        entry.tap()

        // Assert paywall.sheet is visible.
        let sheetElement = app.descendants(matching: .any)
            .matching(identifier: "paywall.sheet")
            .firstMatch
        XCTAssertTrue(
            sheetElement.waitForExistence(timeout: 10),
            "paywall.sheet must appear after tapping the upsell"
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
