import XCTest

// MARK: - DarkModeUITests

/// UI tests for slice #144 — `KIGO_FAKE_APPEARANCE` dark-mode override.
///
/// Launches the app with `KIGO_FAKE_DATE=2026-06-16` and `KIGO_FAKE_APPEARANCE=dark`
/// and asserts that the Today screen renders correctly in dark mode, including:
/// - `kigo.kanji`, `kigo.description`, `microseason.ko`, `info.entry`, and
///   `paywall.entry` all exist within 10 seconds of launch.
/// - A screenshot of the Today screen in dark mode is captured and attached as
///   an `XCTAttachment` with name `"dark-mode-today-screen"` and lifetime `.keepAlways`.
/// - Tapping `paywall.entry` (the gear) presents the Settings sheet containing
///   `paywall.sheet` and, for this active subscriber, `paywall.manage`.
///
/// Screenshot evidence:
/// Attachment name: `"dark-mode-today-screen"`
/// Captured BEFORE the paywall.entry tap, showing the Today screen in dark mode.
/// Full test identifier: KigoUITests/DarkModeUITests/testDarkModeStructuralAssertions
final class DarkModeUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["KIGO_FAKE_DATE"] = "2026-06-16"
        app.launchEnvironment["KIGO_FAKE_APPEARANCE"] = "dark"
        app.launchEnvironment["KIGO_FAKE_ENTITLEMENT"] = "active"
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Structural assertions: Today screen in dark mode + paywall tap

    /// Asserts structural elements are present on the Today screen in dark mode,
    /// captures a screenshot, then taps `paywall.entry` and verifies the sheet.
    ///
    /// Acceptance criteria verified:
    /// AC4: `kigo.kanji`, `kigo.description`, `microseason.ko`, `info.entry`, and
    ///      `paywall.entry` all waitForExistence within 10 s.
    /// AC5: After tapping `paywall.entry` (gear → Settings), `paywall.sheet`
    ///      waitForExistence within 10 s and `paywall.manage` exists (active subscriber).
    /// Screenshot evidence: `dark-mode-today-screen` (XCTAttachment, lifetime .keepAlways)
    ///   captured BEFORE the paywall tap.
    func testDarkModeStructuralAssertions() {
        // --- AC4: Today screen elements present in dark mode ---

        let kanjiElement = app.staticTexts["kigo.kanji"]
        XCTAssertTrue(
            kanjiElement.waitForExistence(timeout: 10),
            "kigo.kanji must exist on the Today screen in dark mode within 10 s"
        )

        let descElement = app.staticTexts["kigo.description"]
        XCTAssertTrue(
            descElement.waitForExistence(timeout: 10),
            "kigo.description must exist on the Today screen in dark mode within 10 s"
        )

        let koElement = app.staticTexts["microseason.ko"]
        XCTAssertTrue(
            koElement.waitForExistence(timeout: 10),
            "microseason.ko must exist on the Today screen in dark mode within 10 s"
        )

        let infoEntry = app.descendants(matching: .any)
            .matching(identifier: "info.entry")
            .firstMatch
        XCTAssertTrue(
            infoEntry.waitForExistence(timeout: 10),
            "info.entry must exist on the Today screen in dark mode within 10 s"
        )

        let paywallEntry = app.buttons["paywall.entry"]
        XCTAssertTrue(
            paywallEntry.waitForExistence(timeout: 10),
            "paywall.entry must exist on the Today screen in dark mode within 10 s"
        )

        // --- Screenshot evidence: Today screen in dark mode (BEFORE paywall tap) ---
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        attachment.name = "dark-mode-today-screen"
        add(attachment)

        // --- AC5: Tap paywall.entry (gear) and verify the Settings sheet ---
        // PRD #189: the gear opens Settings, which for a Premium (active) user shows
        // the subscription-status strip (`paywall.manage`), not the marketing/buy flow
        // — that moved to the dedicated purchase sheet reached from `meaning.upsell`.
        paywallEntry.tap()

        let sheetElement = app.descendants(matching: .any)
            .matching(identifier: "paywall.sheet")
            .firstMatch
        XCTAssertTrue(
            sheetElement.waitForExistence(timeout: 10),
            "paywall.sheet must appear within 10 s after tapping paywall.entry"
        )

        let manageElement = app.descendants(matching: .any)
            .matching(identifier: "paywall.manage")
            .firstMatch
        XCTAssertTrue(
            manageElement.waitForExistence(timeout: 10),
            "paywall.manage must exist in the Settings sheet for an active subscriber"
        )
    }
}
