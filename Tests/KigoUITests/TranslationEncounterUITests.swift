import XCTest

/// UI tests for the English kigo translation (ADR 0024).
///
/// The translation (`kigo.translation`) is part of the FREE Encounter — the
/// English reader's equivalent of being able to read the kanji — so it shows
/// for a Basic (unentitled) user, alongside kanji + reading, while the paid
/// Understanding (`kigo.description`) stays gated. It is English-only: it does
/// not appear in Japanese mode (a Japanese reader takes the meaning from the
/// kanji itself).
///
/// Pinned fixture: KIGO_FAKE_DATE=2026-06-12 (菖蒲), whose bundled
/// `translationEn` is "Sweet flag".
final class TranslationEncounterUITests: XCTestCase {

    private func makeApp(language: String, entitlement: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KIGO_FAKE_DATE"] = "2026-06-12"
        app.launchEnvironment["KIGO_FAKE_LANGUAGE"] = language
        app.launchEnvironment["KIGO_FAKE_ENTITLEMENT"] = entitlement
        return app
    }

    /// Free Encounter: in English mode a Basic (inactive) user sees the
    /// translation — present, non-empty — even though kigo.description (the paid
    /// Understanding) is absent.
    func testTranslationShownFreeInEnglishForBasicUser() {
        let app = makeApp(language: "en", entitlement: "inactive")
        app.launch()

        let translationEl = app.staticTexts["kigo.translation"]
        XCTAssertTrue(
            translationEl.waitForExistence(timeout: 10),
            "kigo.translation must be present in English mode for a Basic user (free Encounter)"
        )
        XCTAssertEqual(
            translationEl.label, "Sweet flag",
            "kigo.translation must show the 2026-06-12 entry's translationEn"
        )

        // The paid Understanding stays gated for a Basic user.
        XCTAssertFalse(
            app.staticTexts["kigo.description"].exists,
            "kigo.description must remain gated for a Basic user even though the translation is free"
        )
    }

    /// English-only: in Japanese mode the translation is absent from the
    /// accessibility hierarchy.
    func testTranslationHiddenInJapaneseMode() {
        let app = makeApp(language: "ja", entitlement: "active")
        app.launch()

        // Wait for the screen to be up via a stable element, then assert absence.
        XCTAssertTrue(
            app.staticTexts["kigo.reading"].waitForExistence(timeout: 10),
            "kigo.reading must exist once the Today screen has loaded"
        )
        XCTAssertFalse(
            app.staticTexts["kigo.translation"].exists,
            "kigo.translation must NOT appear in Japanese mode (English-only content)"
        )
    }
}
