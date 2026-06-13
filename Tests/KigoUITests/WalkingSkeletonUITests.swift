import XCTest

/// UI tests for slice #55 — Walking skeleton.
///
/// Asserts the end-to-end path: app launches, loads the bundled manifest,
/// resolves today's Kigo, and renders a non-empty kanji string identified
/// by the accessibility identifier `kigo.kanji`.
///
/// These tests observe only external, user-visible behaviour — rendered text
/// and presence of identified elements — never internal view structure.
final class WalkingSkeletonUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// AC2 & AC3: A static text element with identifier `kigo.kanji` must be present
    /// and must display non-empty text, proving the full launch→load→resolve→render path
    /// executes on the warm bundled path.
    func testKigoKanjiElementIsPresentAndNonEmpty() {
        // Wait up to 10 seconds for the element to appear (warm bundled path should load quickly).
        let kanjiElement = app.staticTexts["kigo.kanji"]
        XCTAssertTrue(
            kanjiElement.waitForExistence(timeout: 10),
            "A static text element with accessibilityIdentifier 'kigo.kanji' must exist after launch"
        )
        let kanjiText = kanjiElement.label
        XCTAssertFalse(
            kanjiText.isEmpty,
            "The 'kigo.kanji' element must display non-empty text — got: '\(kanjiText)'"
        )
    }
}
