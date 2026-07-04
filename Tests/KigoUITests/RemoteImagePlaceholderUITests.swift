import XCTest

// MARK: - RemoteImagePlaceholderUITests

/// UI tests for slice #228 (PRD #227, C26, ADR 0022) — proves `TodayView`'s new
/// `KigoImageSource` seam call is real wiring, not dead code, by asserting the
/// nil-resolution → placeholder path end to end through the real, reachable app.
///
/// Two launches are asserted, both of which resolve `nil` today (ADR 0022 — the
/// bundled manifest carries no `imageBaseURL` yet, so even the production path is a
/// placeholder render for now):
/// - `KIGO_FAKE_IMAGE=none` — the launch-env fake transport that never yields bytes.
/// - absent (default) — falls through to the production `URLSessionKigoImageTransport`.
///
/// In both cases: `kigo.image` (the existing full-bleed container) and the new
/// `kigo.image.placeholder` marker are present, `kigo.image.remote` (slice #229's
/// loaded-image layer) is absent, and `paywall.entry` stays present and hittable —
/// proving the seam call completed with no crash and no blank render.
///
/// Screenshot evidence:
/// Attachment name: `"remote-image-placeholder-fake-none"`.
/// Captured in `testFakeImageNoneRendersPlaceholderWithIdentifiers`, showing the Today
/// screen's unchanged gradient placeholder after the `KIGO_FAKE_IMAGE=none` seam call.
/// Full test identifier: KigoUITests/RemoteImagePlaceholderUITests/testFakeImageNoneRendersPlaceholderWithIdentifiers
final class RemoteImagePlaceholderUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    /// Launches the app with a pinned date/entitlement (so the Today screen is reached
    /// deterministically) and, when non-nil, the given `KIGO_FAKE_IMAGE` value.
    private func launchApp(fakeImage: String?) {
        app = XCUIApplication()
        app.launchEnvironment["KIGO_FAKE_DATE"] = "2026-06-16"
        app.launchEnvironment["KIGO_FAKE_ENTITLEMENT"] = "active"
        if let fakeImage {
            app.launchEnvironment["KIGO_FAKE_IMAGE"] = fakeImage
        }
        app.launch()
    }

    /// Shared assertions for both launches: `kigo.image` + `kigo.image.placeholder`
    /// present, `kigo.image.remote` absent, `paywall.entry` present and hittable.
    private func assertPlaceholderWiredWithNoRemoteLayer() {
        let image = app.descendants(matching: .any).matching(identifier: "kigo.image").firstMatch
        XCTAssertTrue(
            image.waitForExistence(timeout: 10),
            "kigo.image must exist on the Today screen"
        )

        let placeholder = app.descendants(matching: .any).matching(identifier: "kigo.image.placeholder").firstMatch
        XCTAssertTrue(
            placeholder.waitForExistence(timeout: 10),
            "kigo.image.placeholder must exist, proving the KigoImageSource seam resolved nil rather than being dead code"
        )

        let remote = app.descendants(matching: .any).matching(identifier: "kigo.image.remote").firstMatch
        XCTAssertFalse(
            remote.exists,
            "kigo.image.remote must be absent — real-image rendering is out of scope for this slice (#229)"
        )

        let paywallEntry = app.buttons["paywall.entry"]
        XCTAssertTrue(
            paywallEntry.waitForExistence(timeout: 10),
            "paywall.entry must remain present after the seam call completes"
        )
        XCTAssertTrue(
            paywallEntry.isHittable,
            "paywall.entry must remain hittable after the seam call completes"
        )
    }

    // MARK: - KIGO_FAKE_IMAGE=none

    /// The fake transport yields no bytes; the Today screen renders exactly today's
    /// gradient placeholder with no visual change, and the placeholder identifier
    /// proves the seam was actually called.
    func testFakeImageNoneRendersPlaceholderWithIdentifiers() {
        launchApp(fakeImage: "none")
        assertPlaceholderWiredWithNoRemoteLayer()

        // Screenshot evidence — the unchanged gradient placeholder after the seam call.
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        attachment.name = "remote-image-placeholder-fake-none"
        add(attachment)
    }

    // MARK: - Default launch (no KIGO_FAKE_IMAGE)

    /// No `KIGO_FAKE_IMAGE` set: the production `URLSessionKigoImageTransport`-backed
    /// path is used, which also resolves nil today (the bundled manifest has no
    /// `imageBaseURL` — ADR 0022, expected, not a regression) — behaviour must be
    /// identical to the fake-none launch above.
    func testDefaultLaunchWithoutFakeImageRendersPlaceholderWithIdentifiers() {
        launchApp(fakeImage: nil)
        assertPlaceholderWiredWithNoRemoteLayer()
    }
}
