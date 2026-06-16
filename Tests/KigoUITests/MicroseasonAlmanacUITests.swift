import XCTest

/// UI tests for slice #122 — AlmanacPositions wiring + tappable microseason.timeline.
///
/// Launches the app with `KIGO_FAKE_DATE=2026-06-16` (梅子黄, 芒種) and asserts:
/// - `microseason.sekki` exists and its label contains '芒種'
/// - `microseason.ko` exists and its label contains '梅子黄'
/// - `microseason.timeline` exists and isHittable returns true
///
/// Also captures an XCTAttachment screenshot of the resting Today screen.
///
/// Screenshot test identifier: KigoUITests/MicroseasonAlmanacUITests/testRestingTodayScreen
/// Attachment name: "resting-today-screen"
final class MicroseasonAlmanacUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["KIGO_FAKE_DATE"] = "2026-06-16"
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - AC1: microseason.sekki contains '芒種'

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

    // MARK: - AC2: microseason.ko contains '梅子黄'

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

    // MARK: - AC3: microseason.timeline exists and isHittable

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

    // MARK: - Screenshot evidence

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
}
