import XCTest

/// UI tests for slice #56 — `KIGO_FAKE_DATE` environment override.
///
/// Launches the app with `KIGO_FAKE_DATE=2026-06-12` set in the launch
/// environment and asserts that the `kigo.kanji` element shows the manifest's
/// 06-12 entry kanji ("菖蒲"), proving the override travels through
/// `launchDateProvider` → `ContentStore.dateProvider` → `TodayResolver` →
/// the rendered Today screen.
///
/// The kanji value "菖蒲" is pinned from the committed manifest fixture
/// (Resources/manifest.json, key "06-12"), matching how `ResolutionTests`
/// and `ContentSourceTests` pin values.
final class FakeDateUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Inject the fake date via the launch environment.
        // The app root reads ProcessInfo.processInfo.environment and passes
        // it to launchDateProvider(_:), which returns a FixedDateProvider
        // pinned to 2026-06-12.
        app.launchEnvironment["KIGO_FAKE_DATE"] = "2026-06-12"
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// AC1: With `KIGO_FAKE_DATE=2026-06-12`, the `kigo.kanji` element must
    /// show "菖蒲" — the 06-12 kanji pinned from the bundled manifest fixture.
    func testFakeDateShowsJune12Kanji() {
        let kanjiElement = app.staticTexts["kigo.kanji"]
        XCTAssertTrue(
            kanjiElement.waitForExistence(timeout: 10),
            "A static text element with accessibilityIdentifier 'kigo.kanji' must exist after launch"
        )
        XCTAssertEqual(
            kanjiElement.label,
            "菖蒲",
            "With KIGO_FAKE_DATE=2026-06-12, kigo.kanji must show '菖蒲' (the 06-12 manifest entry)"
        )
    }
}
