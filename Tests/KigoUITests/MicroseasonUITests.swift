import XCTest

/// UI tests for slice #58 — Today screen shows the current Microseason (Kō primary, Sekki secondary).
///
/// Launches the app with `KIGO_FAKE_DATE=2026-06-12` and asserts that:
/// - `microseason.ko` displays the Kō reading "くされたるくさほたるとなる"
/// - `microseason.sekki` displays the Sekki reading "ぼうしゅ"
///
/// Pinned fixture values from Resources/manifest.json, key "06-12":
/// - The Ko whose dateRange contains "06-12": kanji = 腐草為螢, reading = くされたるくさほたるとなる
///   (dateRange: 06-11 to 06-15, sekkiId = "boshu")
/// - The parent Sekki with id "boshu": kanji = 芒種, reading = ぼうしゅ
///
/// Text representation choices:
/// - microseason.ko label: The Kō reading (hiragana), e.g. "くされたるくさほたるとなる"
/// - microseason.sekki label: The Sekki reading (hiragana), e.g. "ぼうしゅ"
final class MicroseasonUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["KIGO_FAKE_DATE"] = "2026-06-12"
        // Pin Japanese so this suite is order-independent: LiveLanguageSwitchUITests
        // (which runs earlier alphabetically) persists .english to UserDefaults via the
        // real Settings picker, and these assertions expect hiragana readings.
        app.launchEnvironment["KIGO_FAKE_LANGUAGE"] = "ja"
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// AC1 + AC2 + AC4: With `KIGO_FAKE_DATE=2026-06-12`, `microseason.ko` must
    /// exist with non-empty text and show the Kō reading pinned from the manifest.
    func testFakeDateShowsJune12KoReading() {
        let koElement = app.staticTexts["microseason.ko"]
        XCTAssertTrue(
            koElement.waitForExistence(timeout: 10),
            "A static text element with accessibilityIdentifier 'microseason.ko' must exist after launch"
        )
        let label = koElement.label
        XCTAssertFalse(
            label.isEmpty,
            "The 'microseason.ko' element must display non-empty text"
        )
        XCTAssertEqual(
            label,
            "くされたるくさほたるとなる",
            "With KIGO_FAKE_DATE=2026-06-12, microseason.ko must show the Kō reading from the 06-12 manifest entry"
        )
    }

    /// AC1 + AC2 + AC4: With `KIGO_FAKE_DATE=2026-06-12`, `microseason.sekki` must
    /// exist with non-empty text and show the parent Sekki reading pinned from the manifest.
    func testFakeDateShowsJune12SekkiReading() {
        let sekkiElement = app.staticTexts["microseason.sekki"]
        XCTAssertTrue(
            sekkiElement.waitForExistence(timeout: 10),
            "A static text element with accessibilityIdentifier 'microseason.sekki' must exist after launch"
        )
        let label = sekkiElement.label
        XCTAssertFalse(
            label.isEmpty,
            "The 'microseason.sekki' element must display non-empty text"
        )
        XCTAssertEqual(
            label,
            "ぼうしゅ",
            "With KIGO_FAKE_DATE=2026-06-12, microseason.sekki must show the Sekki reading 'ぼうしゅ' (parent of the 06-12 Kō)"
        )
    }

    /// AC3: `microseason.ko` (Kō, primary) must appear before `microseason.sekki`
    /// (Sekki, secondary) in the view hierarchy, reflecting the primary/secondary hierarchy.
    func testKoAppearsBeforeSekki() {
        let koElement = app.staticTexts["microseason.ko"]
        let sekkiElement = app.staticTexts["microseason.sekki"]
        XCTAssertTrue(
            koElement.waitForExistence(timeout: 10),
            "microseason.ko must exist"
        )
        XCTAssertTrue(
            sekkiElement.waitForExistence(timeout: 10),
            "microseason.sekki must exist"
        )
        // The Kō element (primary) should appear higher (smaller Y coordinate) than
        // the Sekki element (secondary) in the rendered VStack layout.
        XCTAssertLessThan(
            koElement.frame.minY,
            sekkiElement.frame.minY,
            "microseason.ko (Kō, primary) must appear above microseason.sekki (Sekki, secondary)"
        )
    }
}
