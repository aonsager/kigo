import XCTest

// MARK: - SettingsLanguageUITests

/// UI tests for Slice #136: Reactive chrome-string seam wired end-to-end into PaywallView.
///
/// Acceptance criterion verified:
///   AC: On a default launch (no language env var), `paywall.restore` shows the Japanese
///       restore string ("復元") because `InMemoryLanguageStore` defaults to `.japanese`.
///
/// The test launches without any `KIGO_FAKE_LANGUAGE` override so it exercises the
/// production-default code path (no env-var resolver yet — that is slice #137).
///
/// Screenshot evidence:
///   XCTAttachment name: "paywall-restore-japanese"
///   Lifetime: .keepAlways
///   Test identifier: KigoUITests/SettingsLanguageUITests/testDefaultLaunchShowsJapaneseRestoreString
final class SettingsLanguageUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Fix the date so Today-screen content is deterministic.
        app.launchEnvironment["KIGO_FAKE_DATE"] = "2026-06-12"
        // Inactive entitlement so the paywall shows the buy/restore surface (not manage).
        app.launchEnvironment["KIGO_FAKE_ENTITLEMENT"] = "inactive"
        // Set a fake price so the paywall loads synchronously without StoreKit.
        app.launchEnvironment["KIGO_FAKE_PRICE"] = "¥300"
        // No KIGO_FAKE_LANGUAGE — exercises the production-default .japanese path.
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Default-launch: paywall.restore shows Japanese restore string

    /// On a default launch, `paywall.restore` must display the Japanese restore string ("復元").
    ///
    /// This exercises the full injection chain:
    ///  1. KigoApp creates an `InMemoryLanguageStore()` — defaults to `.japanese`.
    ///  2. `ChromeStrings(.japanese).restore` == "復元".
    ///  3. PaywallView renders the button with that label.
    ///  4. The UI test reads `paywall.restore`'s label and asserts equality.
    func testDefaultLaunchShowsJapaneseRestoreString() {
        // Open the paywall sheet via the upgrade entry.
        let entry = app.descendants(matching: .any)
            .matching(identifier: "paywall.entry")
            .firstMatch
        XCTAssertTrue(
            entry.waitForExistence(timeout: 10),
            "paywall.entry must exist on the Today screen"
        )
        entry.tap()

        // Wait for the paywall sheet to appear.
        let sheet = app.descendants(matching: .any)
            .matching(identifier: "paywall.sheet")
            .firstMatch
        XCTAssertTrue(
            sheet.waitForExistence(timeout: 10),
            "paywall.sheet must appear after tapping paywall.entry"
        )

        // Locate the restore button (search all descendants for resilience to
        // SwiftUI's accessibility element-type mapping on iOS 26).
        let restoreElement = app.descendants(matching: .any)
            .matching(identifier: "paywall.restore")
            .firstMatch
        XCTAssertTrue(
            restoreElement.waitForExistence(timeout: 5),
            "paywall.restore element must exist in the paywall sheet"
        )

        // Assert the label equals the Japanese restore string.
        let label = restoreElement.label
        XCTAssertEqual(
            label, "復元",
            "paywall.restore label must equal '復元' (Japanese restore string) on a default launch; got: '\(label)'"
        )

        // Screenshot evidence — captured AFTER the assertion passes.
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        attachment.name = "paywall-restore-japanese"
        add(attachment)
    }
}
