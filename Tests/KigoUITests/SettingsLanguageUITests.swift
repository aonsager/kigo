import XCTest

// MARK: - SettingsLanguageUITests

/// UI tests for `KIGO_FAKE_LANGUAGE` resolver and chrome-string seam (Slice #136–#137).
///
/// Acceptance criteria verified:
///   AC-ja: Default launch (no language env var) → `paywall.restore` shows "復元".
///   AC-en: `KIGO_FAKE_LANGUAGE=en` launch → `paywall.restore` shows "Restore Purchases".
///   AC-ja-env: `KIGO_FAKE_LANGUAGE=ja` launch → `paywall.restore` shows "復元".
///
/// Screenshot evidence (required for Slice #137):
///   XCTAttachment name: "slice-137-language-en-restore"
///   Lifetime: .keepAlways
///   Test identifier: KigoUITests/SettingsLanguageUITests/testEnvEnglishLaunchShowsEnglishRestoreString
final class SettingsLanguageUITests: XCTestCase {

    // MARK: - Helpers

    /// Shared environment variables common to all tests in this suite.
    private var baseEnvironment: [String: String] {
        [
            "KIGO_FAKE_DATE": "2026-06-12",
            "KIGO_FAKE_ENTITLEMENT": "inactive",
            "KIGO_FAKE_PRICE": "¥300",
        ]
    }

    /// Launches the app and opens the paywall sheet, returning the restore element.
    ///
    /// Asserts the paywall.entry and paywall.sheet exist before returning.
    private func launchAndOpenPaywall(app: XCUIApplication) -> XCUIElement {
        app.launch()

        let entry = app.descendants(matching: .any)
            .matching(identifier: "paywall.entry")
            .firstMatch
        XCTAssertTrue(
            entry.waitForExistence(timeout: 10),
            "paywall.entry must exist on the Today screen"
        )
        entry.tap()

        let sheet = app.descendants(matching: .any)
            .matching(identifier: "paywall.sheet")
            .firstMatch
        XCTAssertTrue(
            sheet.waitForExistence(timeout: 10),
            "paywall.sheet must appear after tapping paywall.entry"
        )

        let restoreElement = app.descendants(matching: .any)
            .matching(identifier: "paywall.restore")
            .firstMatch
        XCTAssertTrue(
            restoreElement.waitForExistence(timeout: 5),
            "paywall.restore element must exist in the paywall sheet"
        )
        return restoreElement
    }

    // MARK: - AC-ja: Default-launch: paywall.restore shows Japanese restore string

    /// On a default launch (no `KIGO_FAKE_LANGUAGE`), `paywall.restore` must show "復元".
    ///
    /// This exercises the full injection chain:
    ///  1. KigoApp calls `launchLanguageStore(environment:)` — no env var → `UserDefaultsLanguageStore`.
    ///  2. `UserDefaultsLanguageStore` with no prior write → defaults to `.japanese`.
    ///  3. `ChromeStrings(.japanese).restore` == "復元".
    ///  4. PaywallView renders the restore button with that label.
    ///
    /// Screenshot evidence:
    ///   XCTAttachment name: "paywall-restore-japanese"
    func testDefaultLaunchShowsJapaneseRestoreString() {
        let app = XCUIApplication()
        baseEnvironment.forEach { app.launchEnvironment[$0.key] = $0.value }
        // No KIGO_FAKE_LANGUAGE — exercises the UserDefaultsLanguageStore default path.

        let restoreElement = launchAndOpenPaywall(app: app)

        let label = restoreElement.label
        XCTAssertEqual(
            label, "復元",
            "paywall.restore label must equal '復元' on a default launch; got: '\(label)'"
        )

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        attachment.name = "paywall-restore-japanese"
        add(attachment)
    }

    // MARK: - AC-en (Slice #137): KIGO_FAKE_LANGUAGE=en → English restore string

    /// Launching with `KIGO_FAKE_LANGUAGE=en` must show "Restore Purchases" on `paywall.restore`.
    ///
    /// This exercises the `launchLanguageStore` resolver:
    ///  1. `KIGO_FAKE_LANGUAGE=en` → locked `InMemoryLanguageStore(.english)`.
    ///  2. `ChromeStrings(.english).restore` == "Restore Purchases".
    ///  3. PaywallView renders the restore button with that label.
    ///
    /// Screenshot evidence (required for Slice #137):
    ///   XCTAttachment name: "slice-137-language-en-restore"
    ///   Lifetime: .keepAlways
    func testEnvEnglishLaunchShowsEnglishRestoreString() {
        let app = XCUIApplication()
        baseEnvironment.forEach { app.launchEnvironment[$0.key] = $0.value }
        app.launchEnvironment["KIGO_FAKE_LANGUAGE"] = "en"

        let restoreElement = launchAndOpenPaywall(app: app)

        let label = restoreElement.label
        XCTAssertEqual(
            label, "Restore Purchases",
            "paywall.restore label must equal 'Restore Purchases' with KIGO_FAKE_LANGUAGE=en; got: '\(label)'"
        )

        // Screenshot evidence — captured AFTER assertion passes.
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        attachment.name = "slice-137-language-en-restore"
        add(attachment)
    }

    // MARK: - AC-ja-env (Slice #137): KIGO_FAKE_LANGUAGE=ja → Japanese restore string

    /// Launching with `KIGO_FAKE_LANGUAGE=ja` must show "復元" on `paywall.restore`.
    ///
    /// This exercises the `launchLanguageStore` resolver:
    ///  1. `KIGO_FAKE_LANGUAGE=ja` → locked `InMemoryLanguageStore(.japanese)`.
    ///  2. `ChromeStrings(.japanese).restore` == "復元".
    ///  3. PaywallView renders the restore button with that label.
    func testEnvJapaneseLaunchShowsJapaneseRestoreString() {
        let app = XCUIApplication()
        baseEnvironment.forEach { app.launchEnvironment[$0.key] = $0.value }
        app.launchEnvironment["KIGO_FAKE_LANGUAGE"] = "ja"

        let restoreElement = launchAndOpenPaywall(app: app)

        let label = restoreElement.label
        XCTAssertEqual(
            label, "復元",
            "paywall.restore label must equal '復元' with KIGO_FAKE_LANGUAGE=ja; got: '\(label)'"
        )
    }
}
