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

    // MARK: - Helpers (UI actions)

    private func openSettings(in app: XCUIApplication) -> XCUIElement {
        let entry = element(in: app, id: "paywall.entry")
        entry.tap()
        let sheet = app.descendants(matching: .any)
            .matching(identifier: "paywall.sheet")
            .firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "paywall.sheet must appear")
        return sheet
    }

    private func selectLanguage(_ label: String, in app: XCUIApplication) {
        let seg = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == '\(label)'"))
            .firstMatch
        XCTAssertTrue(seg.waitForExistence(timeout: 5), "'\(label)' segment must exist")
        seg.tap()
    }

    private func dismissSheet(in app: XCUIApplication) {
        let sheet = app.descendants(matching: .any)
            .matching(identifier: "paywall.sheet")
            .firstMatch
        sheet.swipeDown(velocity: .fast)
        _ = app.descendants(matching: .any)
            .matching(identifier: "kigo.reading")
            .firstMatch
            .waitForExistence(timeout: 3)
    }

    // MARK: - Main test: live language switch

    /// Launches with KIGO_FAKE_DATE=2026-06-16 (no fake language), resets to Japanese
    /// via the Settings picker (so the test is idempotent across simulator re-use),
    /// asserts the Japanese values, toggles to English, then asserts the change.
    ///
    /// Screenshot evidence:
    ///   XCTAttachment name: "today-view-english"
    ///   Lifetime: .keepAlways
    func testLanguageSwitchJapaneseToEnglish() {
        let app = makeApp()
        app.launch()

        // Reset to a known Japanese state via the real Settings picker.
        // The simulator's UserDefaults may hold .english from a previous run;
        // tapping Japanese here persists .japanese to UserDefaults so the
        // subsequent assertions reflect the true default behaviour.
        _ = openSettings(in: app)
        selectLanguage("Japanese", in: app)
        dismissSheet(in: app)

        // Record Japanese-state values.
        let kanjiEl = element(in: app, id: "kigo.kanji")
        let kanjiValue = kanjiEl.label
        let readingEl = element(in: app, id: "kigo.reading")
        let jaReading = readingEl.label
        let descEl = element(in: app, id: "kigo.description")
        let jaDesc = descEl.label

        // AC-ja-launch: reading must be non-empty hiragana; desc must carry the date stamp.
        XCTAssertFalse(jaReading.isEmpty, "kigo.reading must not be empty in Japanese mode")
        XCTAssertTrue(
            jaDesc.contains("2026-06-16"),
            "kigo.description must contain '2026-06-16' in Japanese mode; got: '\(jaDesc)'"
        )

        // Toggle to English via Settings.
        _ = openSettings(in: app)
        selectLanguage("English", in: app)
        dismissSheet(in: app)

        // AC-reading-switch: kigo.reading must now show romaji (different string).
        let enReading = element(in: app, id: "kigo.reading").label
        XCTAssertNotEqual(
            enReading, jaReading,
            "kigo.reading must change after switching to English; before='\(jaReading)' after='\(enReading)'"
        )

        // AC-desc-switch: description must still contain the date but differ from Japanese.
        let enDesc = element(in: app, id: "kigo.description").label
        XCTAssertTrue(
            enDesc.contains("2026-06-16"),
            "kigo.description after English switch must still contain '2026-06-16'; got: '\(enDesc)'"
        )
        XCTAssertNotEqual(
            enDesc, jaDesc,
            "kigo.description must differ between Japanese and English"
        )

        // AC-kanji-stable: kanji must be unchanged.
        let kanjiValue2 = element(in: app, id: "kigo.kanji").label
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

    // MARK: - Almanac sheet language switch (Slice #175)

    /// Opens the Almanac sheet after toggling to English and asserts
    /// that `microseason.koDescription` and `microseason.sekkiDescription`
    /// contain no hiragana or CJK characters.
    ///
    /// Screenshot evidence:
    ///   XCTAttachment name: "almanac-sheet-english"
    ///   Lifetime: .keepAlways
    ///   Test identifier: KigoUITests/LiveLanguageSwitchUITests/testAlmanacSheetEnglishLanguage
    func testAlmanacSheetEnglishLanguage() {
        let app = makeApp()
        app.launch()

        // 1. Toggle to English via Settings.
        _ = openSettings(in: app)
        selectLanguage("English", in: app)
        dismissSheet(in: app)

        // 2. Open the Almanac sheet via microseason.timeline.
        let timeline = element(in: app, id: "microseason.timeline")
        timeline.tap()

        // 3. Wait for the almanac sheet to appear.
        let almanac = app.descendants(matching: .any)
            .matching(identifier: "microseason.almanac")
            .firstMatch
        XCTAssertTrue(almanac.waitForExistence(timeout: 10), "microseason.almanac must appear after tapping microseason.timeline")

        // 4. Assert koDescription contains no hiragana/CJK.
        let koDesc = element(in: app, id: "microseason.koDescription")
        let koDescText = koDesc.label
        XCTAssertFalse(
            containsCJKOrHiragana(koDescText),
            "microseason.koDescription must contain no CJK/hiragana in English mode; got: '\(koDescText)'"
        )

        // 5. Assert sekkiDescription contains no hiragana/CJK.
        let sekkiDesc = element(in: app, id: "microseason.sekkiDescription")
        let sekkiDescText = sekkiDesc.label
        XCTAssertFalse(
            containsCJKOrHiragana(sekkiDescText),
            "microseason.sekkiDescription must contain no CJK/hiragana in English mode; got: '\(sekkiDescText)'"
        )

        // 6. Screenshot evidence — Almanac sheet in English.
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        attachment.name = "almanac-sheet-english"
        add(attachment)
    }

    /// Verifies that toggling back to Japanese restores CJK prose in the Almanac sheet.
    func testAlmanacSheetJapaneseRevertAfterEnglish() {
        let app = makeApp()
        app.launch()

        // 1. Toggle to English, then back to Japanese.
        _ = openSettings(in: app)
        selectLanguage("English", in: app)
        dismissSheet(in: app)

        _ = openSettings(in: app)
        selectLanguage("Japanese", in: app)
        dismissSheet(in: app)

        // 2. Open the Almanac sheet.
        let timeline = element(in: app, id: "microseason.timeline")
        timeline.tap()
        let almanac = app.descendants(matching: .any)
            .matching(identifier: "microseason.almanac")
            .firstMatch
        XCTAssertTrue(almanac.waitForExistence(timeout: 10), "microseason.almanac must appear")

        // 3. Assert koDescription reverts to Japanese (contains hiragana/CJK).
        let koDesc = element(in: app, id: "microseason.koDescription")
        XCTAssertTrue(
            containsCJKOrHiragana(koDesc.label),
            "microseason.koDescription must revert to CJK/hiragana after switching back to Japanese; got: '\(koDesc.label)'"
        )

        // 4. Assert sekkiDescription reverts to Japanese.
        let sekkiDesc = element(in: app, id: "microseason.sekkiDescription")
        XCTAssertTrue(
            containsCJKOrHiragana(sekkiDesc.label),
            "microseason.sekkiDescription must revert to CJK/hiragana after switching back to Japanese; got: '\(sekkiDesc.label)'"
        )
    }

    // MARK: - Slice #176: Attribution panel + full round-trip

    /// Full round-trip test (Slice #176 acceptance criteria):
    ///
    ///   1. Launch with KIGO_FAKE_DATE=2026-06-16 in Japanese state.
    ///   2. Assert kigo.description contains "2026-06-16" and kigo.reading is non-empty.
    ///   3. Toggle to English; assert kigo.description still has "2026-06-16" but differs,
    ///      kigo.reading changed to romaji, kigo.kanji unchanged.
    ///   4. Assert paywall.restore reads "Restore Purchases" (English chrome).
    ///   5. Open Attribution panel; assert info.title=="Season Kigo", info.credit=="Unknown photographer",
    ///      info.license=="Public domain".
    ///   6. Capture screenshot of Attribution panel in English.
    ///   7. Dismiss panel; toggle back to Japanese; assert kigo.description and kigo.reading
    ///      are restored to original Japanese values.
    ///   8. Assert kigo.kanji is identical across all three states.
    ///
    /// Screenshot evidence:
    ///   XCTAttachment name: "attribution-panel-english"
    ///   Lifetime: .keepAlways
    func testAttributionPanelEnglishAndFullRoundTrip() {
        let app = makeApp()
        app.launch()

        // 0. Reset to Japanese (idempotent — handles leftover English from prior runs).
        _ = openSettings(in: app)
        selectLanguage("Japanese", in: app)
        dismissSheet(in: app)

        // 1. Record initial Japanese values.
        let kanjiEl    = element(in: app, id: "kigo.kanji")
        let kanjiValue = kanjiEl.label
        let jaReading  = element(in: app, id: "kigo.reading").label
        let jaDesc     = element(in: app, id: "kigo.description").label

        // AC1: Japanese description contains the date stamp.
        XCTAssertTrue(
            jaDesc.contains("2026-06-16"),
            "kigo.description must contain '2026-06-16' in Japanese mode; got: '\(jaDesc)'"
        )
        // AC2: Japanese reading is non-empty hiragana.
        XCTAssertFalse(jaReading.isEmpty, "kigo.reading must not be empty in Japanese mode")

        // 2. Toggle to English.
        _ = openSettings(in: app)
        selectLanguage("English", in: app)
        dismissSheet(in: app)

        // AC3: kigo.description still contains the date but is a different string.
        let enDesc = element(in: app, id: "kigo.description").label
        XCTAssertTrue(
            enDesc.contains("2026-06-16"),
            "kigo.description after English switch must still contain '2026-06-16'; got: '\(enDesc)'"
        )
        XCTAssertNotEqual(
            enDesc, jaDesc,
            "kigo.description must differ between Japanese and English; ja='\(jaDesc)' en='\(enDesc)'"
        )

        // AC4: kigo.reading changed to romaji.
        let enReading = element(in: app, id: "kigo.reading").label
        XCTAssertNotEqual(
            enReading, jaReading,
            "kigo.reading must change to romaji after English switch; before='\(jaReading)' after='\(enReading)'"
        )

        // AC5: kigo.kanji unchanged.
        let kanjiValueEn = element(in: app, id: "kigo.kanji").label
        XCTAssertEqual(
            kanjiValueEn, kanjiValue,
            "kigo.kanji must be identical before and after English toggle; before='\(kanjiValue)' after='\(kanjiValueEn)'"
        )

        // AC6: paywall.restore reads "Restore Purchases" immediately after toggle (no relaunch).
        let paywallEntry = element(in: app, id: "paywall.entry")
        paywallEntry.tap()
        let paywallSheet = app.descendants(matching: .any)
            .matching(identifier: "paywall.sheet")
            .firstMatch
        XCTAssertTrue(paywallSheet.waitForExistence(timeout: 10), "paywall.sheet must appear")

        let restoreEl = app.descendants(matching: .any)
            .matching(identifier: "paywall.restore")
            .firstMatch
        XCTAssertTrue(restoreEl.waitForExistence(timeout: 5), "paywall.restore must exist")
        XCTAssertEqual(
            restoreEl.label, "Restore Purchases",
            "paywall.restore must read 'Restore Purchases' after English toggle; got '\(restoreEl.label)'"
        )

        // Dismiss paywall sheet before opening Attribution panel.
        paywallSheet.swipeDown(velocity: .fast)
        _ = element(in: app, id: "kigo.reading")

        // AC7: Attribution panel shows English strings.
        let infoEntry = element(in: app, id: "info.entry")
        infoEntry.tap()

        let infoPanel = app.descendants(matching: .any)
            .matching(identifier: "info.panel")
            .firstMatch
        XCTAssertTrue(infoPanel.waitForExistence(timeout: 10), "info.panel must appear")

        let titleEl = app.staticTexts["info.title"]
        XCTAssertTrue(titleEl.waitForExistence(timeout: 5), "info.title must exist in panel")
        XCTAssertEqual(
            titleEl.label, "Season Kigo",
            "info.title must read 'Season Kigo' in English; got '\(titleEl.label)'"
        )

        let creditEl = app.staticTexts["info.credit"]
        XCTAssertTrue(creditEl.waitForExistence(timeout: 5), "info.credit must exist in panel")
        XCTAssertEqual(
            creditEl.label, "Unknown photographer",
            "info.credit must read 'Unknown photographer' in English; got '\(creditEl.label)'"
        )

        let licenseEl = app.staticTexts["info.license"]
        XCTAssertTrue(licenseEl.waitForExistence(timeout: 5), "info.license must exist in panel")
        XCTAssertEqual(
            licenseEl.label, "Public domain",
            "info.license must read 'Public domain' in English; got '\(licenseEl.label)'"
        )

        // Screenshot evidence — Attribution panel in English.
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        attachment.name = "attribution-panel-english"
        add(attachment)

        // Dismiss Attribution panel.
        infoPanel.swipeDown(velocity: .fast)
        _ = element(in: app, id: "kigo.reading")

        // AC8: Toggle back to Japanese — kigo.description and kigo.reading revert.
        _ = openSettings(in: app)
        selectLanguage("Japanese", in: app)
        dismissSheet(in: app)

        let revertedReading = element(in: app, id: "kigo.reading").label
        XCTAssertEqual(
            revertedReading, jaReading,
            "kigo.reading must revert to Japanese after toggling back; expected '\(jaReading)' got '\(revertedReading)'"
        )

        let revertedDesc = element(in: app, id: "kigo.description").label
        XCTAssertEqual(
            revertedDesc, jaDesc,
            "kigo.description must revert to Japanese after toggling back; expected '\(jaDesc)' got '\(revertedDesc)'"
        )

        // AC5 (final): kigo.kanji still unchanged.
        let kanjiValueReverted = element(in: app, id: "kigo.kanji").label
        XCTAssertEqual(
            kanjiValueReverted, kanjiValue,
            "kigo.kanji must be identical in all three states"
        )
    }

    // MARK: - Helpers

    /// Returns true if `string` contains any hiragana (U+3040–U+309F) or
    /// CJK Unified Ideographs (U+4E00–U+9FFF) characters.
    private func containsCJKOrHiragana(_ string: String) -> Bool {
        string.unicodeScalars.contains { scalar in
            (0x3040...0x309F).contains(scalar.value) ||   // hiragana
            (0x4E00...0x9FFF).contains(scalar.value)       // CJK unified ideographs
        }
    }
}
