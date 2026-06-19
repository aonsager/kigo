import XCTest

// MARK: - TodayLayoutUITests

/// UI tests for slice #154 — scrim + top-right gear layout assertions.
///
/// Launches the app with `KIGO_FAKE_DATE=2026-06-16` (梅子黄, 芒種) and asserts:
/// 1. `kigo.image` fills the full screen width (within 5 pt) and at least 90% of screen height.
/// 2. `kigo.scrim` exists in the accessibility hierarchy when the Today screen is visible.
/// 3. `info.entry` is in the top-left quadrant (midX < width/2, midY < height/3).
/// 4. `paywall.entry` is in the top-right quadrant (midX > width/2, midY < height/3).
///
/// Screenshot evidence:
/// Attachment name: `"today-layout-scrim-gear"`
/// Captured in `testScrimPresent` with all four layout elements visible.
/// Full test identifier: KigoUITests/TodayLayoutUITests/testScrimPresent
final class TodayLayoutUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["KIGO_FAKE_DATE"] = "2026-06-16"
        app.launchEnvironment["KIGO_FAKE_ENTITLEMENT"] = "inactive"
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Nonzero-count guard

    /// Ensures the test suite executes at least one meaningful assertion.
    /// This is a tracer that fails if the app doesn't reach the Today screen.
    private func waitForTodayScreen() {
        let kanji = app.staticTexts["kigo.kanji"]
        XCTAssertTrue(
            kanji.waitForExistence(timeout: 10),
            "Today screen (kigo.kanji) must be visible within 10 s — app did not reach the Today screen"
        )
    }

    // MARK: - AC1: testImageFullBleed

    /// kigo.image frame width is within 5 pt of window width and height >= 90% of window height.
    func testImageFullBleed() {
        waitForTodayScreen()

        let windowWidth = app.windows.firstMatch.frame.width
        let windowHeight = app.windows.firstMatch.frame.height

        let imageElement = app.descendants(matching: .any)
            .matching(identifier: "kigo.image")
            .firstMatch
        XCTAssertTrue(
            imageElement.waitForExistence(timeout: 10),
            "kigo.image must exist in the accessibility hierarchy on the Today screen"
        )

        let imageFrame = imageElement.frame
        XCTAssertLessThanOrEqual(
            abs(imageFrame.width - windowWidth),
            5.0,
            "kigo.image width (\(imageFrame.width)) must be within 5 pt of window width (\(windowWidth))"
        )
        XCTAssertGreaterThanOrEqual(
            imageFrame.height,
            windowHeight * 0.9,
            "kigo.image height (\(imageFrame.height)) must be >= 90% of window height (\(windowHeight * 0.9))"
        )
    }

    // MARK: - AC2: testScrimPresent

    /// An element with accessibilityIdentifier kigo.scrim exists when the Today screen is visible.
    /// Also captures the screenshot evidence for this slice.
    func testScrimPresent() {
        waitForTodayScreen()

        let scrim = app.descendants(matching: .any)
            .matching(identifier: "kigo.scrim")
            .firstMatch
        XCTAssertTrue(
            scrim.waitForExistence(timeout: 10),
            "kigo.scrim must exist in the accessibility hierarchy when the Today screen is visible"
        )

        // Screenshot evidence — captures the Today screen with scrim, (i) top-left, gear top-right.
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        attachment.name = "today-layout-scrim-gear"
        add(attachment)
    }

    // MARK: - AC3: testInfoEntryTopLeft

    /// info.entry frame midX < windowWidth/2 and midY < windowHeight/3.
    func testInfoEntryTopLeft() {
        waitForTodayScreen()

        let windowWidth = app.windows.firstMatch.frame.width
        let windowHeight = app.windows.firstMatch.frame.height

        let infoEntry = app.descendants(matching: .any)
            .matching(identifier: "info.entry")
            .firstMatch
        XCTAssertTrue(
            infoEntry.waitForExistence(timeout: 10),
            "info.entry must exist on the Today screen"
        )

        let frame = infoEntry.frame
        let midX = frame.midX
        let midY = frame.midY

        XCTAssertLessThan(
            midX,
            windowWidth / 2,
            "info.entry midX (\(midX)) must be left of screen center (\(windowWidth / 2))"
        )
        XCTAssertLessThan(
            midY,
            windowHeight / 3,
            "info.entry midY (\(midY)) must be in the top third of the screen (< \(windowHeight / 3))"
        )
    }

    // MARK: - AC4: testPaywallEntryTopRight

    /// paywall.entry frame midX > windowWidth/2 and midY < windowHeight/3.
    func testPaywallEntryTopRight() {
        waitForTodayScreen()

        let windowWidth = app.windows.firstMatch.frame.width
        let windowHeight = app.windows.firstMatch.frame.height

        let paywallEntry = app.descendants(matching: .any)
            .matching(identifier: "paywall.entry")
            .firstMatch
        XCTAssertTrue(
            paywallEntry.waitForExistence(timeout: 10),
            "paywall.entry must exist on the Today screen"
        )

        let frame = paywallEntry.frame
        let midX = frame.midX
        let midY = frame.midY

        XCTAssertGreaterThan(
            midX,
            windowWidth / 2,
            "paywall.entry midX (\(midX)) must be right of screen center (\(windowWidth / 2))"
        )
        XCTAssertLessThan(
            midY,
            windowHeight / 3,
            "paywall.entry midY (\(midY)) must be in the top third of the screen (< \(windowHeight / 3))"
        )
    }
}
