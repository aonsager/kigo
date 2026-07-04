import XCTest

// MARK: - SettingsReminderOnUITests
//
/// UI test for the `settings.dailyReminder` toggle shown in its **"on"** state
/// (Slice #220 — the second of two slices for PRD #218 / C23, ADR 0019).
///
/// This is the AC6 screenshot evidence, captured via a **real UI-test app launch**
/// (NOT `ImageRenderer`, which cannot render UIKit-backed `Toggle`/`Picker` controls
/// outside a live window and produced placeholder boxes in attempt 1). The toggle is
/// pre-seeded "on" through the `KIGO_FAKE_REMINDER=on` launch-environment fake
/// (mirroring `KIGO_FAKE_APPEARANCE`), so the test never taps it — tapping would fire
/// the real notification-permission prompt, which hangs headlessly (J9). Under the
/// same fake path the app also resolves an in-memory scheduler, so no real prompt can
/// occur even if scheduling were triggered.
///
/// Screenshot evidence (required for Slice #220):
///   XCTAttachment name: "slice-220-settings-daily-reminder-on"
///   Lifetime: .keepAlways
///   Test identifier: KigoUITests/SettingsReminderOnUITests/testDailyReminderToggleShownOn
final class SettingsReminderOnUITests: XCTestCase {

    /// Launched with `KIGO_FAKE_REMINDER=on` (plus `KIGO_FAKE_DATE`/entitlement fakes
    /// for a deterministic Settings sheet), opens Settings via `paywall.entry`, and
    /// asserts `settings.dailyReminder` exists and reads **on** — without ever tapping it.
    func testDailyReminderToggleShownOn() {
        let app = XCUIApplication()
        app.launchEnvironment["KIGO_FAKE_REMINDER"] = "on"
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

        // The toggle must exist and read "on" (value "1") because of the launch seed.
        // NEVER tap it — see the file doc comment.
        let reminderToggle = app.descendants(matching: .any)
            .matching(identifier: "settings.dailyReminder")
            .firstMatch
        XCTAssertTrue(
            reminderToggle.waitForExistence(timeout: 5),
            "settings.dailyReminder toggle must exist in the Settings sheet"
        )
        XCTAssertEqual(
            reminderToggle.value as? String, "1",
            "settings.dailyReminder must read on when seeded via KIGO_FAKE_REMINDER=on; got value: \(String(describing: reminderToggle.value))"
        )

        // Screenshot evidence for Slice #220 (AC6): real UI-test app launch capture.
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        attachment.name = "slice-220-settings-daily-reminder-on"
        add(attachment)
    }
}
