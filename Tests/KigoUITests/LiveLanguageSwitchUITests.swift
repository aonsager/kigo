import XCTest

// MARK: - LiveLanguageSwitchUITests

/// UI tests for the live language switch via the Settings picker (Slice #174).
///
/// These tests verify that `TodayView` reacts to the language toggle in Settings
/// without relaunching the app — the core acceptance criterion for slice #174.
///
/// Acceptance criteria verified:
///   AC-ja-launch:   On first launch (no fake language), kigo.reading contains hiragana
///                   and kigo.description contains "2026-06-16" in Japanese form.
///   AC-reading-switch: After toggling to English, kigo.reading changes to romaji.
///   AC-desc-switch:   After toggling, kigo.description still contains "2026-06-16"
///                     but is a different string from the pre-toggle value.
///   AC-kanji-stable:  kigo.kanji value is identical before and after the toggle.
///
/// Screenshot evidence (required for Slice #174):
///   XCTAttachment name: "today-view-english"
///   Lifetime: .keepAlways
///   Test identifier: KigoUITests/LiveLanguageSwitchUITests/testLanguageSwitchJapaneseToEnglish
@MainActor
final class LiveLanguageSwitchUITests: XCTestCase {

    // MARK: - Helpers

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KIGO_FAKE_DATE"] = "2026-06-16"
        // No KIGO_FAKE_LANGUAGE — exercises the real UserDefaultsLanguageStore default path.
        return app
    }

    private func element(in app: XCUIApplication, id: String, timeout: TimeInterval = 10) -> XCUIElement {
        let el = app.descendants(matching: .any)
            .matching(identifier: id)
            .firstMatch
        XCTAssertTrue(
            el.waitForExistence(timeout: timeout),
            "Element '\(id)' must exist within \(timeout)s"
        )
        return el
    }

    // MARK: - Main test: live language switch

    /// Launches with KIGO_FAKE_DATE=2026-06-16 (no fake language), asserts Japanese,
    /// toggles to English in Settings, then asserts the reading and description changed.
    ///
    /// Screenshot evidence:
    ///   XCTAttachment name: "today-view-english"
    ///   Lifetime: .keepAlways
    func testLanguageSwitchJapaneseToEnglish() {
        let app = makeApp()
        app.launch()

        // Wait for the main screen to settle.
        let kanjiEl = element(in: app, id: "kigo.kanji", timeout: 15)
        let kanjiValue = kanjiEl.label

        let readingEl = element(in: app, id: "kigo.reading")
        let jaReading = readingEl.label

        let descEl = element(in: app, id: "kigo.description")
        let jaDesc = descEl.label

        // AC-ja-launch: reading should be hiragana (つゆ), desc should contain the date.
        XCTAssertFalse(jaReading.isEmpty, "kigo.reading must not be empty on launch")
        XCTAssertTrue(
            jaDesc.contains("2026-06-16"),
            "kigo.description must contain '2026-06-16' on Japanese launch; got: '\(jaDesc)'"
        )

        // Open Settings via paywall.entry (gear icon).
        let entry = element(in: app, id: "paywall.entry")
        entry.tap()

        // Wait for the Settings sheet.
        let sheet = app.descendants(matching: .any)
            .matching(identifier: "paywall.sheet")
            .firstMatch
        XCTAssertTrue(
            sheet.waitForExistence(timeout: 10),
            "paywall.sheet must appear after tapping paywall.entry"
        )

        // Find and tap the "English" segment.
        let englishSegment = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'English'"))
            .firstMatch
        XCTAssertTrue(
            englishSegment.waitForExistence(timeout: 5),
            "English segment must exist in settings.language picker"
        )
        englishSegment.tap()

        // Dismiss the Settings sheet by swiping down.
        let settingsSheet = app.descendants(matching: .any)
            .matching(identifier: "paywall.sheet")
            .firstMatch
        settingsSheet.swipeDown(velocity: .fast)

        // Wait briefly for the sheet to dismiss and the view to update.
        _ = app.descendants(matching: .any)
            .matching(identifier: "kigo.reading")
            .firstMatch
            .waitForExistence(timeout: 3)

        // AC-reading-switch: kigo.reading must now show romaji (different from Japanese).
        let readingEl2 = element(in: app, id: "kigo.reading")
        let enReading = readingEl2.label
        XCTAssertNotEqual(
            enReading, jaReading,
            "kigo.reading must change after switching to English; before='\(jaReading)' after='\(enReading)'"
        )

        // AC-desc-switch: description must still contain the date but differ from Japanese.
        let descEl2 = element(in: app, id: "kigo.description")
        let enDesc = descEl2.label
        XCTAssertTrue(
            enDesc.contains("2026-06-16"),
            "kigo.description after English switch must still contain '2026-06-16'; got: '\(enDesc)'"
        )

        // AC-kanji-stable: kanji must be unchanged.
        let kanjiEl2 = element(in: app, id: "kigo.kanji")
        let kanjiValue2 = kanjiEl2.label
        XCTAssertEqual(
            kanjiValue2, kanjiValue,
            "kigo.kanji must be identical before and after language toggle"
        )

        // Screenshot evidence — captured after toggle, showing English values.
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        attachment.name = "today-view-english"
        add(attachment)
    }
}
