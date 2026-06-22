import XCTest

/// UI tests for slice #57 — Today screen shows Kigo reading and description.
///
/// Launches the app with `KIGO_FAKE_DATE=2026-06-12` and asserts that:
/// - `kigo.reading` displays the hiragana reading "しょうぶ"
/// - `kigo.description` displays the pinned prose description for 06-12
///
/// Pinned fixture values from Resources/manifest.json, key "06-12":
/// - reading:     しょうぶ
/// - description: Sweet flag — the blade-like iris leaves used in summer
///                purification rites, placed in baths on Tango no Sekku.
final class ReadingDescriptionUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["KIGO_FAKE_DATE"] = "2026-06-12"
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// AC1 + AC4: With `KIGO_FAKE_DATE=2026-06-12`, `kigo.reading` must show
    /// the hiragana reading "しょうぶ" pinned from the bundled manifest fixture.
    func testFakeDateShowsJune12Reading() {
        let readingElement = app.staticTexts["kigo.reading"]
        XCTAssertTrue(
            readingElement.waitForExistence(timeout: 10),
            "A static text element with accessibilityIdentifier 'kigo.reading' must exist after launch"
        )
        XCTAssertEqual(
            readingElement.label,
            "しょうぶ",
            "With KIGO_FAKE_DATE=2026-06-12, kigo.reading must show 'しょうぶ' (the 06-12 manifest entry)"
        )
    }

    /// AC2 + AC4: With `KIGO_FAKE_DATE=2026-06-12`, `kigo.description` must show
    /// the pinned prose description from the bundled manifest fixture.
    func testFakeDateShowsJune12Description() {
        let descriptionElement = app.staticTexts["kigo.description"]
        XCTAssertTrue(
            descriptionElement.waitForExistence(timeout: 10),
            "A static text element with accessibilityIdentifier 'kigo.description' must exist after launch"
        )
        let label = descriptionElement.label
        XCTAssertFalse(
            label.isEmpty,
            "The 'kigo.description' element must display non-empty text"
        )
        XCTAssertEqual(
            label,
            "Sweet flag — the blade-like iris leaves used in summer purification rites, placed in baths on Tango no Sekku. (2026-06-12)",
            "With KIGO_FAKE_DATE=2026-06-12, kigo.description must match the 06-12 manifest entry exactly (including the ADR 0016 date stamp)"
        )
    }
}
