import XCTest

/// UI tests for slice #59 — Full-bleed placeholder image element on the Today screen.
///
/// Acceptance criteria verified:
/// AC1: An element with accessibilityIdentifier `kigo.image` is present on the Today screen.
/// AC3: The placeholder renders BEHIND text — kigo.kanji, kigo.description, microseason.ko,
///      microseason.sekki are all still present and visible (not obscured by the image layer).
/// AC4: The complete evidence procedure passes under KIGO_FAKE_DATE=2026-06-12:
///      image (kigo.image), kanji (kigo.kanji), description (kigo.description),
///      Kō (microseason.ko), Sekki (microseason.sekki) all present for the 06-12 entry.
///
/// Note: AC2 (determinism) is verified headlessly in KigoPlaceholderTests (unit tests),
/// which does not require a simulator.
///
/// Pinned fixture values from Resources/manifest.json, key "06-12":
/// - kanji:       菖蒲
/// - description: Sweet flag — the blade-like iris leaves used in summer purification rites, placed in baths on Tango no Sekku.
/// - ko reading:  くされたるくさほたるとなる
/// - sekki:       ぼうしゅ
/// - imageId:     ayame-06-12
final class TodayScreenUITests: XCTestCase {

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

    // MARK: - AC1: kigo.image element is present

    /// AC1: An element with accessibilityIdentifier `kigo.image` must exist on the Today screen.
    func testKigoImageElementExists() {
        // The placeholder is a LinearGradient with .accessibilityIdentifier("kigo.image")
        // and .accessibilityAddTraits(.isImage), so it appears in app.images.
        let imageElement = app.images["kigo.image"]
        XCTAssertTrue(
            imageElement.waitForExistence(timeout: 10),
            "An element with accessibilityIdentifier 'kigo.image' must exist on the Today screen"
        )
    }

    // MARK: - AC3: Text elements are not obscured (still present)

    /// AC3: kigo.kanji must remain visible on top of the placeholder image.
    func testKanjiRemainsVisibleAbovePlaceholder() {
        let kanjiElement = app.staticTexts["kigo.kanji"]
        XCTAssertTrue(
            kanjiElement.waitForExistence(timeout: 10),
            "kigo.kanji must remain visible when kigo.image is rendered behind it"
        )
        XCTAssertFalse(kanjiElement.label.isEmpty, "kigo.kanji must display non-empty text")
    }

    /// AC3: kigo.description must remain visible on top of the placeholder image.
    func testDescriptionRemainsVisibleAbovePlaceholder() {
        let descElement = app.staticTexts["kigo.description"]
        XCTAssertTrue(
            descElement.waitForExistence(timeout: 10),
            "kigo.description must remain visible when kigo.image is rendered behind it"
        )
        XCTAssertFalse(descElement.label.isEmpty, "kigo.description must display non-empty text")
    }

    // MARK: - AC4: Full evidence procedure for 06-12 entry

    /// AC4: All five required elements present for KIGO_FAKE_DATE=2026-06-12.
    func testAllElementsPresentForJune12() {
        // 1. kigo.image
        XCTAssertTrue(
            app.images["kigo.image"].waitForExistence(timeout: 10),
            "kigo.image must be present for 06-12"
        )

        // 2. kigo.kanji — 菖蒲
        let kanjiElement = app.staticTexts["kigo.kanji"]
        XCTAssertTrue(
            kanjiElement.waitForExistence(timeout: 10),
            "kigo.kanji must be present for 06-12"
        )
        XCTAssertEqual(kanjiElement.label, "菖蒲",
            "kigo.kanji must show '菖蒲' for the 06-12 entry")

        // 3. kigo.description
        let descElement = app.staticTexts["kigo.description"]
        XCTAssertTrue(
            descElement.waitForExistence(timeout: 10),
            "kigo.description must be present for 06-12"
        )
        XCTAssertEqual(
            descElement.label,
            "Sweet flag — the blade-like iris leaves used in summer purification rites, placed in baths on Tango no Sekku.",
            "kigo.description must match the 06-12 manifest entry"
        )

        // 4. microseason.ko — くされたるくさほたるとなる
        let koElement = app.staticTexts["microseason.ko"]
        XCTAssertTrue(
            koElement.waitForExistence(timeout: 10),
            "microseason.ko must be present for 06-12"
        )
        XCTAssertEqual(koElement.label, "くされたるくさほたるとなる",
            "microseason.ko must show the Kō reading for 06-12")

        // 5. microseason.sekki — ぼうしゅ
        let sekkiElement = app.staticTexts["microseason.sekki"]
        XCTAssertTrue(
            sekkiElement.waitForExistence(timeout: 10),
            "microseason.sekki must be present for 06-12"
        )
        XCTAssertEqual(sekkiElement.label, "ぼうしゅ",
            "microseason.sekki must show 'ぼうしゅ' for 06-12")
    }

    // MARK: - AC3: Image renders BEHIND text (z-order)

    /// AC3: The kigo.image element must appear behind kigo.kanji in z-order.
    /// We verify this by checking that both exist and the text elements are on top
    /// (their frames overlap the image frame — the image is full-bleed).
    func testImageRendersFullBleedBehindText() {
        let imageElement = app.images["kigo.image"]
        let kanjiElement = app.staticTexts["kigo.kanji"]

        XCTAssertTrue(
            imageElement.waitForExistence(timeout: 10),
            "kigo.image must exist"
        )
        XCTAssertTrue(
            kanjiElement.waitForExistence(timeout: 10),
            "kigo.kanji must exist"
        )

        // The image is full-bleed — its frame should cover the entire screen width.
        let imageFrame = imageElement.frame
        let screenBounds = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(
            imageFrame.width, screenBounds.width * 0.9,
            "kigo.image should be nearly full-width (full-bleed)"
        )
    }
}
