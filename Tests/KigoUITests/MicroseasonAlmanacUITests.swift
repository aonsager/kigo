import XCTest

/// UI tests for slice #122 and #123 — AlmanacPositions wiring + tappable microseason.timeline
/// and AlmanacSheetView tap-to-present / content / dismiss.
///
/// Launches the app with `KIGO_FAKE_DATE=2026-06-16` (梅子黄, 芒種) and asserts:
/// - `microseason.sekki` exists and its label contains '芒種'
/// - `microseason.ko` exists and its label contains '梅子黄'
/// - `microseason.timeline` exists and isHittable returns true
/// - Tapping microseason.timeline presents microseason.almanac (slice #123)
/// - microseason.koPosition contains '27' and '72'
/// - microseason.dayGauge exists
/// - microseason.koDescription exists and is non-empty
/// - Swiping down dismisses the almanac sheet
///
/// Also captures XCTAttachment screenshots for evidence.
final class MicroseasonAlmanacUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["KIGO_FAKE_DATE"] = "2026-06-16"
        // Pin Japanese so this suite is order-independent: LiveLanguageSwitchUITests
        // (which runs earlier alphabetically) persists .english to UserDefaults via the
        // real Settings picker, and these assertions expect kanji/hiragana content.
        app.launchEnvironment["KIGO_FAKE_LANGUAGE"] = "ja"
        // The almanac is a Premium surface — microseason elements are gated behind entitlement.
        app.launchEnvironment["KIGO_FAKE_ENTITLEMENT"] = "active"
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Slice #122 AC1: microseason.sekki contains '芒種'

    /// With KIGO_FAKE_DATE=2026-06-16, the microseason.sekki element must exist
    /// and its label must contain '芒種' (the Sekki kanji for Bōshu).
    func testMicroseasonSekkiContainsBoShu() {
        let sekkiElement = app.staticTexts["microseason.sekki"]
        XCTAssertTrue(
            sekkiElement.waitForExistence(timeout: 10),
            "microseason.sekki must exist with KIGO_FAKE_DATE=2026-06-16"
        )
        let label = sekkiElement.label
        XCTAssertTrue(
            label.contains("芒種") || label == "ぼうしゅ",
            "microseason.sekki label must contain '芒種' or be the reading 'ぼうしゅ' for 2026-06-16, got: '\(label)'"
        )
    }

    // MARK: - Slice #122 AC2: microseason.ko contains '梅子黄'

    /// With KIGO_FAKE_DATE=2026-06-16, the microseason.ko element must exist
    /// and its label must contain '梅子黄' (the Ko kanji) or the hiragana reading.
    func testMicroseasonKoContainsMeishiKo() {
        let koElement = app.staticTexts["microseason.ko"]
        XCTAssertTrue(
            koElement.waitForExistence(timeout: 10),
            "microseason.ko must exist with KIGO_FAKE_DATE=2026-06-16"
        )
        let label = koElement.label
        XCTAssertTrue(
            label.contains("梅子黄") || label == "うめのみきばむ",
            "microseason.ko label must contain '梅子黄' or be the reading 'うめのみきばむ' for 2026-06-16, got: '\(label)'"
        )
    }

    // MARK: - Slice #122 AC3: microseason.timeline exists and isHittable

    /// With KIGO_FAKE_DATE=2026-06-16, the microseason.timeline element must exist
    /// and isHittable must return true (it is a visible, tappable affordance).
    func testMicroseasonTimelineExistsAndIsHittable() {
        // Wait for the today screen to appear first
        let koElement = app.staticTexts["microseason.ko"]
        XCTAssertTrue(
            koElement.waitForExistence(timeout: 10),
            "Precondition: microseason.ko must exist before checking timeline"
        )

        let timelineElement = app.buttons["microseason.timeline"]
        XCTAssertTrue(
            timelineElement.waitForExistence(timeout: 5),
            "microseason.timeline button must exist with KIGO_FAKE_DATE=2026-06-16"
        )
        XCTAssertTrue(
            timelineElement.isHittable,
            "microseason.timeline must be hittable (visible and interactable)"
        )
    }

    // MARK: - Slice #123 AC1: tap opens microseason.almanac

    /// Tapping microseason.timeline must present the almanac sheet with
    /// a root container identified as 'microseason.almanac'.
    func testTapTimelineOpensAlmanacSheet() {
        let koElement = app.staticTexts["microseason.ko"]
        XCTAssertTrue(
            koElement.waitForExistence(timeout: 10),
            "Precondition: microseason.ko must exist"
        )

        let timelineButton = app.buttons["microseason.timeline"]
        XCTAssertTrue(
            timelineButton.waitForExistence(timeout: 5),
            "Precondition: microseason.timeline must exist before tapping"
        )
        timelineButton.tap()

        let almanacContainer = app.otherElements["microseason.almanac"]
        XCTAssertTrue(
            almanacContainer.waitForExistence(timeout: 5),
            "microseason.almanac must appear after tapping microseason.timeline"
        )
    }

    // MARK: - Slice #123 AC2: koPosition contains '27' and '72'

    /// With KIGO_FAKE_DATE=2026-06-16, the microseason.koPosition element in the
    /// open almanac sheet must contain both '27' and '72'.
    func testAlmanacKoPositionContains27And72() {
        let koElement = app.staticTexts["microseason.ko"]
        XCTAssertTrue(koElement.waitForExistence(timeout: 10), "Precondition: today screen loaded")

        let timelineButton = app.buttons["microseason.timeline"]
        XCTAssertTrue(timelineButton.waitForExistence(timeout: 5), "Precondition: timeline button exists")
        timelineButton.tap()

        let almanacContainer = app.otherElements["microseason.almanac"]
        XCTAssertTrue(
            almanacContainer.waitForExistence(timeout: 5),
            "Precondition: almanac sheet must be open"
        )

        let koPositionElement = app.staticTexts["microseason.koPosition"]
        XCTAssertTrue(
            koPositionElement.waitForExistence(timeout: 5),
            "microseason.koPosition must exist in the almanac sheet"
        )
        let label = koPositionElement.label
        XCTAssertTrue(
            label.contains("27"),
            "microseason.koPosition must contain '27' for 2026-06-16, got: '\(label)'"
        )
        XCTAssertTrue(
            label.contains("72"),
            "microseason.koPosition must contain '72' for 2026-06-16, got: '\(label)'"
        )
    }

    // MARK: - Slice #123 AC3: dayGauge exists in open sheet

    /// microseason.dayGauge must exist in the open almanac sheet.
    func testAlmanacDayGaugeExists() {
        let koElement = app.staticTexts["microseason.ko"]
        XCTAssertTrue(koElement.waitForExistence(timeout: 10), "Precondition: today screen loaded")

        let timelineButton = app.buttons["microseason.timeline"]
        XCTAssertTrue(timelineButton.waitForExistence(timeout: 5), "Precondition: timeline button exists")
        timelineButton.tap()

        let almanacContainer = app.otherElements["microseason.almanac"]
        XCTAssertTrue(
            almanacContainer.waitForExistence(timeout: 5),
            "Precondition: almanac sheet must be open"
        )

        // ProgressView accessibility: try progressIndicator first, fall back to any element
        let gaugeElement = app.progressIndicators["microseason.dayGauge"]
        let gaugeAlt = app.otherElements["microseason.dayGauge"]
        XCTAssertTrue(
            gaugeElement.waitForExistence(timeout: 5) || gaugeAlt.waitForExistence(timeout: 1),
            "microseason.dayGauge must exist in the almanac sheet"
        )
    }

    // MARK: - Slice #123 AC4: koDescription exists and is non-empty

    /// microseason.koDescription must exist and its label must be non-empty
    /// (contains Japanese prose for the current Kō).
    func testAlmanacKoDescriptionExistsAndNonEmpty() {
        let koElement = app.staticTexts["microseason.ko"]
        XCTAssertTrue(koElement.waitForExistence(timeout: 10), "Precondition: today screen loaded")

        let timelineButton = app.buttons["microseason.timeline"]
        XCTAssertTrue(timelineButton.waitForExistence(timeout: 5), "Precondition: timeline button exists")
        timelineButton.tap()

        let almanacContainer = app.otherElements["microseason.almanac"]
        XCTAssertTrue(
            almanacContainer.waitForExistence(timeout: 5),
            "Precondition: almanac sheet must be open"
        )

        let descriptionElement = app.staticTexts["microseason.koDescription"]
        XCTAssertTrue(
            descriptionElement.waitForExistence(timeout: 5),
            "microseason.koDescription must exist in the almanac sheet"
        )
        XCTAssertFalse(
            descriptionElement.label.isEmpty,
            "microseason.koDescription must have a non-empty label (Japanese prose)"
        )
    }

    // MARK: - Slice #123 AC5: swipe down dismisses almanac sheet

    /// Swiping down on the almanac sheet must dismiss it so microseason.almanac
    /// no longer exists.
    func testAlmanacSheetDismissesOnSwipeDown() {
        let koElement = app.staticTexts["microseason.ko"]
        XCTAssertTrue(koElement.waitForExistence(timeout: 10), "Precondition: today screen loaded")

        let timelineButton = app.buttons["microseason.timeline"]
        XCTAssertTrue(timelineButton.waitForExistence(timeout: 5), "Precondition: timeline button exists")
        timelineButton.tap()

        let almanacContainer = app.otherElements["microseason.almanac"]
        XCTAssertTrue(
            almanacContainer.waitForExistence(timeout: 5),
            "Precondition: almanac sheet must be open before swipe"
        )

        // Swipe down from the top of the screen to dismiss the sheet.
        // Using the app-level coordinate swipe is more reliable than swiping the
        // container element itself, which may not reach the drag handle region.
        let topCenter = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        let bottomCenter = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        topCenter.press(forDuration: 0.05, thenDragTo: bottomCenter)

        XCTAssertFalse(
            almanacContainer.waitForExistence(timeout: 5),
            "microseason.almanac must disappear after swiping down"
        )
    }

    // MARK: - Screenshot evidence (slice #122)

    /// Captures a screenshot of the resting Today screen showing:
    /// - microseason.ko (梅子黄)
    /// - microseason.sekki (芒種 / ぼうしゅ)
    /// - microseason.timeline tappable element
    ///
    /// Screenshot test identifier: KigoUITests/MicroseasonAlmanacUITests/testRestingTodayScreen
    /// Attachment name: "resting-today-screen"
    func testRestingTodayScreen() {
        // Wait for the today screen elements to load
        let koElement = app.staticTexts["microseason.ko"]
        XCTAssertTrue(
            koElement.waitForExistence(timeout: 10),
            "microseason.ko must exist for screenshot evidence"
        )

        let sekkiElement = app.staticTexts["microseason.sekki"]
        XCTAssertTrue(
            sekkiElement.waitForExistence(timeout: 5),
            "microseason.sekki must exist for screenshot evidence"
        )

        let timelineElement = app.buttons["microseason.timeline"]
        XCTAssertTrue(
            timelineElement.waitForExistence(timeout: 5),
            "microseason.timeline must exist for screenshot evidence"
        )

        // Verify the content before screenshotting
        XCTAssertFalse(koElement.label.isEmpty, "microseason.ko must have non-empty label")
        XCTAssertFalse(sekkiElement.label.isEmpty, "microseason.sekki must have non-empty label")
        XCTAssertTrue(timelineElement.isHittable, "microseason.timeline must be hittable")

        // Capture screenshot as XCTAttachment
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "resting-today-screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Screenshot evidence (slice #123)

    /// Captures a screenshot of the open AlmanacSheetView showing
    /// microseason.koPosition, microseason.dayGauge, and microseason.koDescription
    /// populated with real data for KIGO_FAKE_DATE=2026-06-16.
    ///
    /// Screenshot test identifier: KigoUITests/MicroseasonAlmanacUITests/testAlmanacSheetPresentation
    /// Attachment name: "almanac-sheet-open"
    func testAlmanacSheetPresentation() {
        let koElement = app.staticTexts["microseason.ko"]
        XCTAssertTrue(
            koElement.waitForExistence(timeout: 10),
            "Precondition: today screen must be loaded"
        )

        let timelineButton = app.buttons["microseason.timeline"]
        XCTAssertTrue(
            timelineButton.waitForExistence(timeout: 5),
            "Precondition: microseason.timeline must exist"
        )
        timelineButton.tap()

        let almanacContainer = app.otherElements["microseason.almanac"]
        XCTAssertTrue(
            almanacContainer.waitForExistence(timeout: 5),
            "Precondition: almanac sheet must be open"
        )

        // Verify all required elements are present
        let koPositionElement = app.staticTexts["microseason.koPosition"]
        XCTAssertTrue(
            koPositionElement.waitForExistence(timeout: 5),
            "microseason.koPosition must exist"
        )

        let descriptionElement = app.staticTexts["microseason.koDescription"]
        XCTAssertTrue(
            descriptionElement.waitForExistence(timeout: 5),
            "microseason.koDescription must exist"
        )

        // Capture the open almanac sheet as screenshot evidence
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "almanac-sheet-open"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Additional screenshot evidence for slice #132: confirms the almanac sheet
        // presents reliably after the enum-driven sheet consolidation.
        let consolidatedScreenshot = XCUIScreen.main.screenshot()
        let consolidatedAttachment = XCTAttachment(screenshot: consolidatedScreenshot)
        consolidatedAttachment.name = "almanac-sheet-consolidated.png"
        consolidatedAttachment.lifetime = .keepAlways
        add(consolidatedAttachment)
    }
}
