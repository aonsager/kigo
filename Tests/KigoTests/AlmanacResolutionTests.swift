import XCTest
import SwiftUI
@testable import Kigo

// MARK: - AlmanacResolutionTests

/// Tests for `AlmanacResolver` and `AlmanacPositions` (slice #106, C11 walking skeleton).
///
/// Verifies:
/// - AC1: `AlmanacResolver` resolves an injected date + bundled manifest to `AlmanacPositions`.
/// - AC2: For 2026-06-16 (梅子黄), the Kō year-position is 27 of 72, 1-indexed.
/// - AC3: The Kō ordering is risshun-anchored (02-04 start) — verified by the 27/72 result.
/// - AC4: Resolver is deterministic — same inputs produce equal `AlmanacPositions`.
///
/// Screenshot evidence (AC6): a host-rendered PNG of "27 / 72" is emitted as an XCTAttachment.
final class AlmanacResolutionTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a UTC `Date` for the given month and day (year is irrelevant for MM-DD lookup).
    private func makeUTCDate(month: Int, day: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var comps = DateComponents()
        comps.year = 2026
        comps.month = month
        comps.day = day
        comps.hour = 12
        return cal.date(from: comps)!
    }

    /// Loads the bundled manifest from the test host app bundle.
    private func loadBundledManifest() throws -> Manifest {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "manifest", withExtension: "json"),
            "manifest.json must be bundled in the Kigo app target"
        )
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    // MARK: - AC1: Resolver produces an AlmanacPositions value

    /// AC1: `AlmanacResolver.resolve(date:manifest:)` returns a non-nil `AlmanacPositions`
    /// for a valid date against the bundled manifest.
    func testResolverReturnsAlmanacPositionsForValidDate() throws {
        let manifest = try loadBundledManifest()
        let date = makeUTCDate(month: 6, day: 16)

        let positions = AlmanacResolver.resolve(date: date, manifest: manifest)

        XCTAssertNotNil(positions, "AlmanacResolver must return non-nil AlmanacPositions for 06-16")
    }

    // MARK: - AC2 & AC3: Kō year-position for 2026-06-16 is 27/72 (risshun-anchored)

    /// AC2 + AC3: For 06-16 (梅子黄), the risshun-anchored Kō year-position is 27 of 72.
    ///
    /// 梅子黄 (range 06-16 – 06-20) is at 1-indexed position 27 in the ordering that
    /// starts at 立春/risshun (the Ko with dateRange.start = "02-04"), not at 01-01.
    /// If the ordering were calendar-anchored (01-01), the position would be different.
    func testKoYearPositionFor0616Is27of72() throws {
        let manifest = try loadBundledManifest()
        let date = makeUTCDate(month: 6, day: 16)

        let positions = try XCTUnwrap(
            AlmanacResolver.resolve(date: date, manifest: manifest),
            "AlmanacResolver must return non-nil AlmanacPositions for 06-16"
        )

        XCTAssertEqual(positions.koYearPosition, 27,
            "Kō year-position for 06-16 (梅子黄) must be 27 under risshun-anchored ordering")
        XCTAssertEqual(positions.koYearTotal, 72,
            "Kō year total must be exactly 72")
    }

    // MARK: - AC4: Determinism — same inputs yield equal AlmanacPositions

    /// AC4: Calling `AlmanacResolver.resolve` twice with identical inputs produces equal results.
    func testResolverIsDeterministic() throws {
        let manifest = try loadBundledManifest()
        let date = makeUTCDate(month: 6, day: 16)

        let positions1 = AlmanacResolver.resolve(date: date, manifest: manifest)
        let positions2 = AlmanacResolver.resolve(date: date, manifest: manifest)

        XCTAssertEqual(positions1, positions2,
            "AlmanacResolver must be deterministic — same inputs must produce equal AlmanacPositions")
    }

    // MARK: - Extra: Boundary dates

    /// First Ko in risshun-anchored ordering: 東風解凍 (02-04 – 02-08) → position 1/72.
    func testFirstKoInRisshunAnchoredOrderingIsPosition1() throws {
        let manifest = try loadBundledManifest()
        let date = makeUTCDate(month: 2, day: 4)

        let positions = try XCTUnwrap(
            AlmanacResolver.resolve(date: date, manifest: manifest),
            "AlmanacResolver must return non-nil AlmanacPositions for 02-04"
        )

        XCTAssertEqual(positions.koYearPosition, 1,
            "The Ko starting on 02-04 (risshun anchor) must be position 1 under risshun-anchored ordering")
        XCTAssertEqual(positions.koYearTotal, 72,
            "Kō year total must be exactly 72")
    }

    // MARK: - AC6: Screenshot evidence — host-render "27 / 72" via ImageRenderer

    /// Screenshot evidence: renders a SwiftUI Text view showing "27 / 72" (driven by the REAL
    /// AlmanacResolver output for 2026-06-16) and emits a PNG as a keepAlways XCTAttachment.
    ///
    /// Full identifier: KigoTests/AlmanacResolutionTests/testKoYearPositionHostRender
    /// Attachment name: "slice-106-ko-position"
    @MainActor
    func testKoYearPositionHostRender() throws {
        let manifest = try loadBundledManifest()
        let date = makeUTCDate(month: 6, day: 16)

        let positions = try XCTUnwrap(
            AlmanacResolver.resolve(date: date, manifest: manifest),
            "AlmanacResolver must return non-nil AlmanacPositions for 06-16"
        )

        // Build the debug view using the REAL resolver output
        let displayText = "\(positions.koYearPosition) / \(positions.koYearTotal)"
        let debugView = ZStack {
            Color(white: 0.1)
            VStack(spacing: 8) {
                Text("Kō Year Position")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(displayText)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("梅子黄 · 2026-06-16")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .frame(width: 300, height: 160)

        let renderer = ImageRenderer(content: debugView)
        renderer.scale = 2.0

        guard let uiImage = renderer.uiImage else {
            XCTFail("ImageRenderer failed to produce a UIImage for the Kō year-position view")
            return
        }

        guard let pngData = uiImage.pngData() else {
            XCTFail("Failed to convert UIImage to PNG data")
            return
        }

        let attachment = XCTAttachment(data: pngData, uniformTypeIdentifier: "public.png")
        attachment.name = "slice-106-ko-position"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Also assert the rendered text matches the expected value
        XCTAssertEqual(displayText, "27 / 72",
            "Host-rendered text must show '27 / 72' for 2026-06-16")
    }

    // MARK: - Slice #107: Sekki year-position tests

    /// AC1 + AC2 + AC3: For 06-16 (芒種), the risshun-anchored Sekki year-position is 9 of 24.
    ///
    /// 芒種 (Bōshu) contains 梅子黄. In the risshun-anchored ordering of 24 Sekki,
    /// 芒種 must be at position 9.
    func testSekkiYearPositionFor0616Is9of24() throws {
        let manifest = try loadBundledManifest()
        let date = makeUTCDate(month: 6, day: 16)

        let positions = try XCTUnwrap(
            AlmanacResolver.resolve(date: date, manifest: manifest),
            "AlmanacResolver must return non-nil AlmanacPositions for 06-16"
        )

        XCTAssertEqual(positions.sekkiYearPosition, 9,
            "Sekki year-position for 06-16 (芒種) must be 9 under risshun-anchored ordering")
        XCTAssertEqual(positions.sekkiYearTotal, 24,
            "Sekki year total must be exactly 24")
    }

    /// AC3: The first Sekki in risshun-anchored ordering (立春) is position 1/24.
    func testFirstSekkiInRisshunAnchoredOrderingIsPosition1() throws {
        let manifest = try loadBundledManifest()
        let date = makeUTCDate(month: 2, day: 4)

        let positions = try XCTUnwrap(
            AlmanacResolver.resolve(date: date, manifest: manifest),
            "AlmanacResolver must return non-nil AlmanacPositions for 02-04"
        )

        XCTAssertEqual(positions.sekkiYearPosition, 1,
            "The Sekki containing the Ko starting on 02-04 (立春/risshun) must be position 1")
        XCTAssertEqual(positions.sekkiYearTotal, 24,
            "Sekki year total must be exactly 24")
    }

    // MARK: - Slice #108: Day-within-Kō tests

    /// AC: For 2026-06-16 (start of 梅子黄, range 06-16–06-20) the day-within-Kō is 1 and
    /// the Kō range length is 5.
    func testDayWithinKoFor0616IsDayOneOfFive() throws {
        let manifest = try loadBundledManifest()
        let date = makeUTCDate(month: 6, day: 16)

        let positions = try XCTUnwrap(
            AlmanacResolver.resolve(date: date, manifest: manifest),
            "AlmanacResolver must return non-nil AlmanacPositions for 06-16"
        )

        XCTAssertEqual(positions.dayWithinKo, 1,
            "Day-within-Kō for 06-16 (start of 梅子黄) must be 1")
        XCTAssertEqual(positions.koRangeLength, 5,
            "Kō range length for 梅子黄 (06-16 – 06-20) must be 5")
    }

    /// AC: For 2026-06-18 (mid-range of 梅子黄, range 06-16–06-20) the day-within-Kō is 3 of 5.
    func testDayWithinKoFor0618IsDayThreeOfFive() throws {
        let manifest = try loadBundledManifest()
        let date = makeUTCDate(month: 6, day: 18)

        let positions = try XCTUnwrap(
            AlmanacResolver.resolve(date: date, manifest: manifest),
            "AlmanacResolver must return non-nil AlmanacPositions for 06-18"
        )

        XCTAssertEqual(positions.dayWithinKo, 3,
            "Day-within-Kō for 06-18 (mid-range of 梅子黄) must be 3")
        XCTAssertEqual(positions.koRangeLength, 5,
            "Kō range length for 梅子黄 (06-16 – 06-20) must be 5")
    }

    /// AC: On a Kō-boundary start day (06-16) the day-within-Kō resets to 1.
    /// This is equivalent to the 06-16 test above, explicitly verifying the boundary reset.
    func testDayWithinKoResetsToBoundaryStartDay() throws {
        let manifest = try loadBundledManifest()

        // Test another Kō boundary start date (02-04, 東風解凍 / risshun Kō start)
        let date = makeUTCDate(month: 2, day: 4)

        let positions = try XCTUnwrap(
            AlmanacResolver.resolve(date: date, manifest: manifest),
            "AlmanacResolver must return non-nil AlmanacPositions for 02-04"
        )

        XCTAssertEqual(positions.dayWithinKo, 1,
            "Day-within-Kō for 02-04 (start of risshun Kō) must be 1")
    }

    /// AC: 02-29 resolves to a defined day-within-Kō without crashing.
    /// 02-29 falls in 霞始靆 (range 02-24–02-29), so day-within-Kō = 6, length = 6.
    func testDayWithinKoFor0229LeapDay() throws {
        let manifest = try loadBundledManifest()

        // Use a leap year so makeUTCDate can produce Feb 29
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var comps = DateComponents()
        comps.year = 2024  // leap year
        comps.month = 2
        comps.day = 29
        comps.hour = 12
        let date = cal.date(from: comps)!

        let positions = try XCTUnwrap(
            AlmanacResolver.resolve(date: date, manifest: manifest),
            "AlmanacResolver must return non-nil AlmanacPositions for 02-29"
        )

        XCTAssertEqual(positions.dayWithinKo, 6,
            "Day-within-Kō for 02-29 (end of 霞始靆, range 02-24–02-29) must be 6")
        XCTAssertEqual(positions.koRangeLength, 6,
            "Kō range length for 霞始靆 (02-24 – 02-29) must be 6")
    }

    // MARK: - Screenshot evidence: day-within-Kō host render (slice #108)

    /// Screenshot evidence: renders a SwiftUI Text view showing "Day 3 / 5" (driven by the REAL
    /// AlmanacResolver output for 2026-06-18) and emits a PNG as a keepAlways XCTAttachment.
    ///
    /// Full identifier: KigoTests/AlmanacResolutionTests/testDayWithinKoHostRender
    /// Attachment name: "slice-108-day-within-ko"
    @MainActor
    func testDayWithinKoHostRender() throws {
        let manifest = try loadBundledManifest()
        let date = makeUTCDate(month: 6, day: 18)

        let positions = try XCTUnwrap(
            AlmanacResolver.resolve(date: date, manifest: manifest),
            "AlmanacResolver must return non-nil AlmanacPositions for 06-18"
        )

        let displayText = "Day \(positions.dayWithinKo) / \(positions.koRangeLength)"

        let debugView = ZStack {
            Color(white: 0.1)
            VStack(spacing: 8) {
                Text("Day within Kō")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(displayText)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("梅子黄 · 2026-06-18")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .frame(width: 300, height: 160)

        let renderer = ImageRenderer(content: debugView)
        renderer.scale = 2.0

        guard let uiImage = renderer.uiImage else {
            XCTFail("ImageRenderer failed to produce a UIImage for the day-within-Kō view")
            return
        }

        guard let pngData = uiImage.pngData() else {
            XCTFail("Failed to convert UIImage to PNG data")
            return
        }

        let attachment = XCTAttachment(data: pngData, uniformTypeIdentifier: "public.png")
        attachment.name = "slice-108-day-within-ko"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Assert the rendered text matches the expected value
        XCTAssertEqual(displayText, "Day 3 / 5",
            "Host-rendered text must show 'Day 3 / 5' for 2026-06-18")
    }

    // MARK: - Screenshot evidence: Kō + Sekki combined host render (slice #107)

    /// Screenshot evidence: renders a SwiftUI view showing BOTH "Kō 27 / 72" AND "Sekki 9 / 24"
    /// (driven by the REAL AlmanacResolver output for 2026-06-16) and emits a PNG as a
    /// keepAlways XCTAttachment.
    ///
    /// Full identifier: KigoTests/AlmanacResolutionTests/testKoAndSekkiPositionHostRender
    /// Attachment name: "slice-107-ko-sekki-position"
    @MainActor
    func testKoAndSekkiPositionHostRender() throws {
        let manifest = try loadBundledManifest()
        let date = makeUTCDate(month: 6, day: 16)

        let positions = try XCTUnwrap(
            AlmanacResolver.resolve(date: date, manifest: manifest),
            "AlmanacResolver must return non-nil AlmanacPositions for 06-16"
        )

        let koText = "\(positions.koYearPosition) / \(positions.koYearTotal)"
        let sekkiText = "\(positions.sekkiYearPosition) / \(positions.sekkiYearTotal)"

        let debugView = ZStack {
            Color(white: 0.1)
            VStack(spacing: 12) {
                Text("2026-06-16 · 梅子黄 · 芒種")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 32) {
                    VStack(spacing: 4) {
                        Text("Kō")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(koText)
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    VStack(spacing: 4) {
                        Text("Sekki")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(sekkiText)
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(24)
        }
        .frame(width: 360, height: 180)

        let renderer = ImageRenderer(content: debugView)
        renderer.scale = 2.0

        guard let uiImage = renderer.uiImage else {
            XCTFail("ImageRenderer failed to produce a UIImage for the Kō+Sekki position view")
            return
        }

        guard let pngData = uiImage.pngData() else {
            XCTFail("Failed to convert UIImage to PNG data")
            return
        }

        let attachment = XCTAttachment(data: pngData, uniformTypeIdentifier: "public.png")
        attachment.name = "slice-107-ko-sekki-position"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Assert both values match expected
        XCTAssertEqual(koText, "27 / 72",
            "Host-rendered Kō text must show '27 / 72' for 2026-06-16")
        XCTAssertEqual(sekkiText, "9 / 24",
            "Host-rendered Sekki text must show '9 / 24' for 2026-06-16")
    }
}
