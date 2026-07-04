import XCTest
import KigoCore
import KigoCoreTestSupport
@testable import Kigo

// MARK: - NotificationSchedulerTests
//
// Slice #220 (PRD #218, C23, ADR 0019): verifies the daily-reminder scheduling
// *decision logic* headlessly, driving `ReminderNotificationCoordinator` through an
// injected `InMemoryNotificationScheduler` with a `ContentStore` over a
// `FixedDateProvider`. No test touches `UNUserNotificationCenter` or a real
// permission prompt.
//
// Acceptance criteria covered here:
//  AC1: enabling schedules exactly one repeating daily request at 08:00 local.
//  AC2: the scheduled request carries today's Kigo kanji + reading (2026-06-16 → 梅雨 / つゆ).
//  AC3: disabling cancels every previously scheduled request (zero pending afterward).
@MainActor
final class NotificationSchedulerTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a UTC `Date` at noon for the given month/day (noon avoids any
    /// local-timezone day-boundary drift in day-key derivation).
    private func makeUTCDate(year: Int = 2026, month: Int, day: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var comps = DateComponents()
        comps.year = year
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

    /// A `ContentStore` over the bundled manifest pinned to the given date, loaded.
    private func makeLoadedStore(month: Int, day: Int) async throws -> ContentStore {
        let manifest = try loadBundledManifest()
        let source = FakeContentSource(manifest: manifest)
        let store = ContentStore(
            source: source,
            dateProvider: FixedDateProvider(date: makeUTCDate(month: month, day: day))
        )
        await store.waitForLoad()
        return store
    }

    // MARK: - AC1: enabling schedules exactly one daily request at 08:00

    func testEnablingSchedulesExactlyOneDailyRequestAt0800() async throws {
        let scheduler = InMemoryNotificationScheduler()
        let store = try await makeLoadedStore(month: 6, day: 16)
        let coordinator = ReminderNotificationCoordinator(scheduler: scheduler, contentStore: store)

        await coordinator.apply(isEnabled: true)

        XCTAssertEqual(
            scheduler.pendingRequests.count, 1,
            "Enabling the reminder must schedule exactly one daily request"
        )
        let request = try XCTUnwrap(scheduler.pendingRequests.first)
        XCTAssertEqual(request.hour, 8, "The daily reminder must fire at hour 08")
        XCTAssertEqual(request.minute, 0, "The daily reminder must fire at minute 00")
    }

    /// Re-enabling must not stack requests — still exactly one.
    func testReEnablingKeepsExactlyOneRequest() async throws {
        let scheduler = InMemoryNotificationScheduler()
        let store = try await makeLoadedStore(month: 6, day: 16)
        let coordinator = ReminderNotificationCoordinator(scheduler: scheduler, contentStore: store)

        await coordinator.apply(isEnabled: true)
        await coordinator.apply(isEnabled: true)

        XCTAssertEqual(
            scheduler.pendingRequests.count, 1,
            "Re-enabling must not accumulate duplicate requests"
        )
    }

    // MARK: - AC2: scheduled content carries today's Kigo kanji + reading

    func testScheduledContentCarriesTodaysKigoKanjiAndReading() async throws {
        let scheduler = InMemoryNotificationScheduler()
        let store = try await makeLoadedStore(month: 6, day: 16)
        let coordinator = ReminderNotificationCoordinator(scheduler: scheduler, contentStore: store)

        await coordinator.apply(isEnabled: true)

        let request = try XCTUnwrap(scheduler.pendingRequests.first)

        // The bundled manifest's 2026-06-16 Kigo is 梅雨 / つゆ.
        XCTAssertEqual(
            request.content.kanji, "梅雨",
            "The scheduled request must carry 2026-06-16's Kigo kanji (梅雨)"
        )
        XCTAssertEqual(
            request.content.reading, "つゆ",
            "The scheduled request must carry 2026-06-16's Kigo reading (つゆ)"
        )

        // And it must match whatever the ContentStore/DateProvider seam resolves,
        // not a hardcoded constant that could drift from the manifest.
        let resolved = try XCTUnwrap(store.todayResolved())
        XCTAssertEqual(request.content.kanji, resolved.kigoEntry.kanji)
        XCTAssertEqual(request.content.reading, resolved.kigoEntry.reading.ja)
    }

    // MARK: - AC3: disabling cancels every previously scheduled request

    func testDisablingCancelsAllPreviouslyScheduledRequests() async throws {
        let scheduler = InMemoryNotificationScheduler()
        let store = try await makeLoadedStore(month: 6, day: 16)
        let coordinator = ReminderNotificationCoordinator(scheduler: scheduler, contentStore: store)

        await coordinator.apply(isEnabled: true)
        XCTAssertEqual(scheduler.pendingRequests.count, 1, "Precondition: one request scheduled")

        await coordinator.apply(isEnabled: false)

        XCTAssertTrue(
            scheduler.pendingRequests.isEmpty,
            "Disabling the reminder must leave zero pending requests"
        )
    }

    // MARK: - Fake scheduler basics

    func testFakeSchedulerRecordsAndClears() async {
        let scheduler = InMemoryNotificationScheduler()
        XCTAssertTrue(scheduler.pendingRequests.isEmpty, "A fresh fake scheduler has no requests")

        await scheduler.scheduleDaily(hour: 8, minute: 0, content: ReminderContent(kanji: "雪", reading: "ゆき"))
        XCTAssertEqual(scheduler.pendingRequests.count, 1)

        await scheduler.cancelAll()
        XCTAssertTrue(scheduler.pendingRequests.isEmpty, "cancelAll clears recorded requests")
    }
}
