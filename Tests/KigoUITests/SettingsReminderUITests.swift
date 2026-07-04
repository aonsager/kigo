import XCTest

// MARK: - SettingsReminderUITests

/// UI test for the `settings.dailyReminder` toggle (Slice #219 — the first of
/// two slices for PRD #218 / C23, ADR 0019).
///
/// This suite proves *presence and default-off state only*. It must never tap
/// the toggle: enabling it is wired to the real notification-permission prompt
/// in slice #220, which hangs headless under `xcodebuild test` (see the
/// StoreKit-trap-shaped gotcha in CLAUDE.md and J9 in docs/GOAL.md).
///
/// Screenshot evidence (required for Slice #219):
///   XCTAttachment name: "slice-219-settings-daily-reminder-off"
///   Lifetime: .keepAlways
///   Test identifier: KigoUITests/SettingsReminderUITests/testDailyReminderToggleOffByDefault
final class SettingsReminderUITests: XCTestCase {

    /// Launched with `KIGO_FAKE_DATE=2026-06-16` and `KIGO_FAKE_ENTITLEMENT=inactive`
    /// (per docs/GOAL.md C23 evidence step 2), opens Settings via `paywall.entry`,
    /// and asserts `settings.dailyReminder` exists and is off — alongside the
    /// existing `settings.language`, `settings.appearance`, and `paywall.restore` rows.
    func testDailyReminderToggleOffByDefault() {
        let app = XCUIApplication()
        app.launchEnvironment["KIGO_FAKE_DATE"] = "2026-06-16"
        app.launchEnvironment["KIGO_FAKE_ENTITLEMENT"] = "inactive"
        app.launchEnvironment["KIGO_FAKE_PRICE"] = "¥300"
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

        // The existing rows must still be present alongside the new toggle.
        let languagePicker = app.descendants(matching: .any)
            .matching(identifier: "settings.language")
            .firstMatch
        XCTAssertTrue(
            languagePicker.waitForExistence(timeout: 5),
            "settings.language must still be present in the Settings sheet"
        )

        let appearancePicker = app.descendants(matching: .any)
            .matching(identifier: "settings.appearance")
            .firstMatch
        XCTAssertTrue(
            appearancePicker.waitForExistence(timeout: 5),
            "settings.appearance must still be present in the Settings sheet"
        )

        let restoreElement = app.descendants(matching: .any)
            .matching(identifier: "paywall.restore")
            .firstMatch
        XCTAssertTrue(
            restoreElement.waitForExistence(timeout: 5),
            "paywall.restore must still be present in the Settings sheet"
        )

        // The new toggle: must exist and be off. NEVER tap it — see the file doc comment.
        let reminderToggle = app.descendants(matching: .any)
            .matching(identifier: "settings.dailyReminder")
            .firstMatch
        XCTAssertTrue(
            reminderToggle.waitForExistence(timeout: 5),
            "settings.dailyReminder toggle must exist in the Settings sheet"
        )
        XCTAssertEqual(
            reminderToggle.value as? String, "0",
            "settings.dailyReminder must be off by default on a fresh install; got value: \(String(describing: reminderToggle.value))"
        )

        // Screenshot evidence for Slice #219.
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        attachment.name = "slice-219-settings-daily-reminder-off"
        add(attachment)
    }
}
