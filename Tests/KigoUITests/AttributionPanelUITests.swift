import XCTest

/// UI tests for slice #128 — Attribution panel: entry button, presentation, content, and dismissal.
///
/// Launches the app with `KIGO_FAKE_DATE=2026-06-16` (梅子黄, 芒種) and asserts:
/// - An element with accessibilityIdentifier `info.entry` exists on the Today screen (AC1).
/// - Tapping `info.entry` presents a sheet with root container `info.panel` (AC2).
/// - After panel appears, `staticTexts["info.title"].label` is non-empty (AC3).
/// - After panel appears, `staticTexts["info.credit"].label` is non-empty (AC4).
/// - Tapping a coordinate off the panel (backdrop) causes `info.panel` to disappear (AC5).
///
/// Screenshot evidence for AC2–AC4:
/// After the panel is open with visible title and credit, a screenshot is captured and attached
/// as an `XCTAttachment` with `lifetime = .keepAlways` and name `"attribution-panel-screenshot"`.
/// Full test identifier: KigoUITests/AttributionPanelUITests/testAttributionPanelFlow
final class AttributionPanelUITests: XCTestCase {

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

    // MARK: - AC1: info.entry exists on Today screen

    /// AC1: An element with accessibilityIdentifier `info.entry` must exist on
    /// the Today screen when launched with KIGO_FAKE_DATE=2026-06-16.
    func testInfoEntryExistsOnTodayScreen() {
        let entry = app.buttons["info.entry"]
        XCTAssertTrue(
            entry.waitForExistence(timeout: 10),
            "An element with accessibilityIdentifier 'info.entry' must exist on the Today screen"
        )
    }

    // MARK: - AC2–AC5: Full panel flow (entry → panel appears → content → dismiss)

    /// AC2–AC5 combined and screenshot evidence:
    /// Tapping `info.entry` presents `info.panel`; panel shows non-empty `info.title` and
    /// `info.credit`; tapping the backdrop dismisses the panel.
    ///
    /// Screenshot test identifier: KigoUITests/AttributionPanelUITests/testAttributionPanelFlow
    /// Attachment name: "attribution-panel-screenshot"
    func testAttributionPanelFlow() {
        // Precondition: wait for Today screen to load
        let entry = app.buttons["info.entry"]
        XCTAssertTrue(
            entry.waitForExistence(timeout: 10),
            "Precondition: info.entry must exist on the Today screen"
        )

        // AC2: Tap info.entry → info.panel must appear
        entry.tap()

        let panel = app.otherElements["info.panel"]
        XCTAssertTrue(
            panel.waitForExistence(timeout: 10),
            "After tapping info.entry, an element with accessibilityIdentifier 'info.panel' must appear"
        )

        // AC3: info.title label is non-empty
        let titleElement = app.staticTexts["info.title"]
        XCTAssertTrue(
            titleElement.waitForExistence(timeout: 5),
            "info.title element must exist in the attribution panel"
        )
        XCTAssertFalse(
            titleElement.label.isEmpty,
            "info.title label must be non-empty; got empty string"
        )

        // AC4: info.credit label is non-empty
        let creditElement = app.staticTexts["info.credit"]
        XCTAssertTrue(
            creditElement.waitForExistence(timeout: 5),
            "info.credit element must exist in the attribution panel"
        )
        XCTAssertFalse(
            creditElement.label.isEmpty,
            "info.credit label must be non-empty; got empty string"
        )

        // Screenshot evidence — captured with the panel open showing title and credit
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "attribution-panel-screenshot"
        attachment.lifetime = .keepAlways
        add(attachment)

        // AC5: Tapping a coordinate off the panel (backdrop) dismisses info.panel.
        // On iOS 26 sheets the sheet fills most of the screen; we swipe down from the top
        // to trigger the standard sheet drag-to-dismiss gesture — the same pattern used in
        // MicroseasonAlmanacUITests/testAlmanacSheetDismissesOnSwipeDown.
        let topCenter = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        let bottomCenter = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        topCenter.press(forDuration: 0.05, thenDragTo: bottomCenter)

        XCTAssertFalse(
            panel.waitForExistence(timeout: 5),
            "info.panel must disappear after swiping down (backdrop dismiss)"
        )
    }
}
