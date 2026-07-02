import XCTest

/// UI tests for slice #190 — Entitlement gate on kigo.description.
/// Extended in slice #191 — Entitlement gate on microseason block (ko/sekki/timeline).
///
/// Two cases:
///   Basic (KIGO_FAKE_ENTITLEMENT=inactive):
///     - kigo.image, kigo.kanji, kigo.reading, meaning.upsell are present.
///     - kigo.description is absent from the accessibility hierarchy.
///     - microseason.ko, microseason.sekki, microseason.timeline are absent.
///     - Tapping meaning.upsell presents a sheet containing paywall.benefits.
///
///   Premium (KIGO_FAKE_ENTITLEMENT=active):
///     - kigo.description is present with non-empty text.
///     - meaning.upsell is absent from the accessibility hierarchy.
///     - microseason.ko and microseason.sekki are present with non-empty text.
///     - microseason.timeline is present and tappable.
///
/// Screenshot evidence:
///   Test identifier: KigoUITests/MeaningGateUITests/testBasicGateShowsUpsell
///   Attachment name: "basic-meaning-gate"
///   Lifetime: .keepAlways
///
///   Test identifier: KigoUITests/MeaningGateUITests/testPremiumGateShowsDescriptionAndMicroseason
///   Attachment name: "premium-today-screen"
///   Lifetime: .keepAlways
///   (J5 evidence: full understanding layer rendered for Premium user)
///
/// Pinned fixture: KIGO_FAKE_DATE=2026-06-12 (菖蒲)
final class MeaningGateUITests: XCTestCase {

    // MARK: - Helpers

    private func makeApp(entitlement: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KIGO_FAKE_DATE"] = "2026-06-12"
        app.launchEnvironment["KIGO_FAKE_LANGUAGE"] = "ja"
        app.launchEnvironment["KIGO_FAKE_ENTITLEMENT"] = entitlement
        return app
    }

    // MARK: - Basic case (inactive entitlement)

    /// AC1: Launched with KIGO_FAKE_ENTITLEMENT=inactive, meaning.upsell is visible
    /// and kigo.description is absent. Also asserts kigo.image, kigo.kanji, kigo.reading present.
    ///
    /// Screenshot evidence:
    ///   Attachment name: "basic-meaning-gate"
    ///   Lifetime: .keepAlways
    func testBasicGateShowsUpsell() {
        let app = makeApp(entitlement: "inactive")
        app.launch()

        // kigo.kanji must be present.
        let kanjiEl = app.staticTexts["kigo.kanji"]
        XCTAssertTrue(
            kanjiEl.waitForExistence(timeout: 10),
            "kigo.kanji must be present in Basic (inactive) case"
        )
        XCTAssertFalse(kanjiEl.label.isEmpty, "kigo.kanji must be non-empty")

        // kigo.reading must be present.
        let readingEl = app.staticTexts["kigo.reading"]
        XCTAssertTrue(
            readingEl.waitForExistence(timeout: 10),
            "kigo.reading must be present in Basic (inactive) case"
        )
        XCTAssertFalse(readingEl.label.isEmpty, "kigo.reading must be non-empty")

        // kigo.image must be present.
        let imageEl = app.images["kigo.image"]
        XCTAssertTrue(
            imageEl.waitForExistence(timeout: 10),
            "kigo.image must be present in Basic (inactive) case"
        )

        // meaning.upsell must be present.
        let upsellEl = app.buttons["meaning.upsell"]
        XCTAssertTrue(
            upsellEl.waitForExistence(timeout: 10),
            "meaning.upsell must be present when KIGO_FAKE_ENTITLEMENT=inactive"
        )

        // kigo.description must NOT be present.
        let descEl = app.staticTexts["kigo.description"]
        XCTAssertFalse(
            descEl.exists,
            "kigo.description must NOT be in the accessibility hierarchy when KIGO_FAKE_ENTITLEMENT=inactive"
        )

        // microseason.ko must NOT be present (C22/2 gate).
        let koEl = app.staticTexts["microseason.ko"]
        XCTAssertFalse(
            koEl.exists,
            "microseason.ko must NOT be in the accessibility hierarchy when KIGO_FAKE_ENTITLEMENT=inactive"
        )

        // microseason.sekki must NOT be present (C22/2 gate).
        let sekkiEl = app.staticTexts["microseason.sekki"]
        XCTAssertFalse(
            sekkiEl.exists,
            "microseason.sekki must NOT be in the accessibility hierarchy when KIGO_FAKE_ENTITLEMENT=inactive"
        )

        // microseason.timeline must NOT be present (C22/2 gate).
        let timelineEl = app.buttons["microseason.timeline"]
        XCTAssertFalse(
            timelineEl.exists,
            "microseason.timeline must NOT be in the accessibility hierarchy when KIGO_FAKE_ENTITLEMENT=inactive"
        )

        // Screenshot evidence — Basic case showing meaning.upsell in place of kigo.description.
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        attachment.name = "basic-meaning-gate"
        add(attachment)
    }

    /// AC3: Tapping meaning.upsell presents a sheet containing paywall.benefits.
    func testTappingUpsellPresentsPaywall() {
        let app = makeApp(entitlement: "inactive")
        app.launch()

        let upsellEl = app.buttons["meaning.upsell"]
        XCTAssertTrue(
            upsellEl.waitForExistence(timeout: 10),
            "meaning.upsell must be present before tapping"
        )

        upsellEl.tap()

        // paywall.benefits must appear in the presented sheet.
        let benefitsEl = app.descendants(matching: .any)
            .matching(identifier: "paywall.benefits")
            .firstMatch
        XCTAssertTrue(
            benefitsEl.waitForExistence(timeout: 10),
            "paywall.benefits must appear after tapping meaning.upsell"
        )
    }

    // MARK: - Premium case (active entitlement)

    /// AC2 + C22/2: Launched with KIGO_FAKE_ENTITLEMENT=active, kigo.description is present
    /// with non-empty text, meaning.upsell is absent, and microseason elements are present.
    ///
    /// Screenshot evidence (J5): full understanding layer rendered calmly for a Premium user.
    ///   Attachment name: "premium-today-screen"
    ///   Lifetime: .keepAlways
    func testPremiumGateShowsDescriptionAndMicroseason() {
        let app = makeApp(entitlement: "active")
        app.launch()

        // kigo.description must be present and non-empty.
        let descEl = app.staticTexts["kigo.description"]
        XCTAssertTrue(
            descEl.waitForExistence(timeout: 10),
            "kigo.description must be present when KIGO_FAKE_ENTITLEMENT=active"
        )
        XCTAssertFalse(
            descEl.label.isEmpty,
            "kigo.description must have non-empty text in Premium case"
        )

        // meaning.upsell must NOT be present.
        let upsellEl = app.buttons["meaning.upsell"]
        XCTAssertFalse(
            upsellEl.exists,
            "meaning.upsell must NOT be in the accessibility hierarchy when KIGO_FAKE_ENTITLEMENT=active"
        )

        // microseason.ko must be present and non-empty (C22/2).
        let koEl = app.staticTexts["microseason.ko"]
        XCTAssertTrue(
            koEl.waitForExistence(timeout: 10),
            "microseason.ko must be present when KIGO_FAKE_ENTITLEMENT=active"
        )
        XCTAssertFalse(
            koEl.label.isEmpty,
            "microseason.ko must have non-empty text in Premium case"
        )

        // microseason.sekki must be present and non-empty (C22/2).
        let sekkiEl = app.staticTexts["microseason.sekki"]
        XCTAssertTrue(
            sekkiEl.waitForExistence(timeout: 10),
            "microseason.sekki must be present when KIGO_FAKE_ENTITLEMENT=active"
        )
        XCTAssertFalse(
            sekkiEl.label.isEmpty,
            "microseason.sekki must have non-empty text in Premium case"
        )

        // microseason.timeline must be present and tappable (C22/2).
        let timelineEl = app.buttons["microseason.timeline"]
        XCTAssertTrue(
            timelineEl.waitForExistence(timeout: 10),
            "microseason.timeline must be present when KIGO_FAKE_ENTITLEMENT=active"
        )
        XCTAssertTrue(
            timelineEl.isHittable,
            "microseason.timeline must be hittable in Premium case"
        )

        // Screenshot evidence (J5): full understanding layer — description + ko + sekki + timeline.
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        attachment.name = "premium-today-screen"
        add(attachment)
    }
}
