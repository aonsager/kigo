import XCTest

// MARK: - RemoteImageUITests

/// UI tests for slice #228/#229 (PRD #227, C26, ADR 0022) — proves `TodayView`'s
/// `KigoImageSource` seam call is real wiring, not dead code, by asserting both the
/// nil-resolution → placeholder path AND the loaded-resolution → real-photo path end
/// to end through the real, reachable app.
///
/// Three launches are asserted:
/// - `KIGO_FAKE_IMAGE=none` — the launch-env fake transport that never yields bytes;
///   resolves `nil` (placeholder path).
/// - absent (default) — falls through to the production `URLSessionKigoImageTransport`
///   path, which also resolves `nil` today (ADR 0022 — the bundled manifest carries no
///   `imageBaseURL` yet).
/// - `KIGO_FAKE_IMAGE=loaded` (slice #229) — the launch-env fake transport paired with
///   a synthetic `imageBaseURL` override, so the real `KigoImageSource.image(manifest:
///   imageId:)` call path resolves known, decodable bytes and `TodayView` renders them
///   full-bleed in place of the gradient placeholder.
///
/// In the two nil-resolution cases: `kigo.image` and `kigo.image.placeholder` are
/// present, `kigo.image.remote` is absent. In the loaded case: `kigo.image` and
/// `kigo.image.remote` are present, `kigo.image.placeholder` is absent. `paywall.entry`
/// stays present and hittable in every case — proving the seam call completed with no
/// crash and no blank render.
///
/// Screenshot evidence:
/// - Attachment name: `"remote-image-placeholder-fake-none"`.
///   Captured in `testFakeImageNoneRendersPlaceholderWithIdentifiers`, showing the
///   Today screen's unchanged gradient placeholder after the `KIGO_FAKE_IMAGE=none`
///   seam call.
///   Full test identifier: KigoUITests/RemoteImageUITests/testFakeImageNoneRendersPlaceholderWithIdentifiers
/// - Attachment name: `"remote-image-loaded-photo"`.
///   Captured in `testFakeImageLoadedRendersRemotePhotoThenNoneStillRendersPlaceholder`,
///   showing the Today screen rendering the fetched photo full-bleed after the
///   `KIGO_FAKE_IMAGE=loaded` seam call, before the same test relaunches with
///   `KIGO_FAKE_IMAGE=none` to prove the placeholder path still works unchanged.
///   Full test identifier: KigoUITests/RemoteImageUITests/testFakeImageLoadedRendersRemotePhotoThenNoneStillRendersPlaceholder
final class RemoteImageUITests: XCTestCase {

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
    private func launchApp(fakeImage: String?, date: String = "2026-06-16") {
        app = XCUIApplication()
        app.launchEnvironment["KIGO_FAKE_DATE"] = date
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

    // MARK: - KIGO_FAKE_IMAGE=loaded (slice #229)

    /// Shared assertions for the loaded-image launch: `kigo.image` + `kigo.image.remote`
    /// present, `kigo.image.placeholder` absent, `paywall.entry` present and hittable.
    private func assertRemoteImageWiredWithNoPlaceholderLayer() {
        let image = app.descendants(matching: .any).matching(identifier: "kigo.image").firstMatch
        XCTAssertTrue(
            image.waitForExistence(timeout: 10),
            "kigo.image must exist on the Today screen"
        )

        let remote = app.descendants(matching: .any).matching(identifier: "kigo.image.remote").firstMatch
        XCTAssertTrue(
            remote.waitForExistence(timeout: 10),
            "kigo.image.remote must exist once KigoImageSource resolves real bytes (KIGO_FAKE_IMAGE=loaded)"
        )

        let placeholder = app.descendants(matching: .any).matching(identifier: "kigo.image.placeholder").firstMatch
        XCTAssertFalse(
            placeholder.exists,
            "kigo.image.placeholder must be absent once the remote image has rendered"
        )

        let paywallEntry = app.buttons["paywall.entry"]
        XCTAssertTrue(
            paywallEntry.waitForExistence(timeout: 10),
            "paywall.entry must remain present after the loaded-image render"
        )
        XCTAssertTrue(
            paywallEntry.isHittable,
            "paywall.entry must remain hittable after the loaded-image render"
        )
    }

    /// Slice #229: proves the real-photo render and the placeholder-fallback render
    /// coexist correctly within a single test. First launch resolves real bytes
    /// (`KIGO_FAKE_IMAGE=loaded`) and the fetched photo renders full-bleed with
    /// `kigo.image.remote` present and `kigo.image.placeholder` absent. The same test
    /// then relaunches with `KIGO_FAKE_IMAGE=none`, proving the placeholder path still
    /// renders correctly afterward — neither path regressed the other.
    func testFakeImageLoadedRendersRemotePhotoThenNoneStillRendersPlaceholder() {
        launchApp(fakeImage: "loaded", date: "2026-06-12")
        assertRemoteImageWiredWithNoPlaceholderLayer()

        // Screenshot evidence — the real fetched photo rendering full-bleed.
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        attachment.name = "remote-image-loaded-photo"
        add(attachment)

        app.terminate()
        launchApp(fakeImage: "none", date: "2026-06-12")
        assertPlaceholderWiredWithNoRemoteLayer()
    }
}
