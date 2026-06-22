import XCTest
import SwiftUI
@testable import Kigo

// MARK: - C2MigrationScreenshotTests

/// Screenshot evidence for the C2 migration (ADR 0016/0018): proves the migrated,
/// localized 2026 dataset resolves and renders through the REAL data path.
///
/// The path exercised is fully real: `BundledContentSource` decodes the committed
/// `manifest.json` (now absolute `2026-MM-DD` keys + `LocalizedText` reading/description)
/// → `TodayResolver.resolve` looks up the Kigo by `DayKey.absolute` and the Kō by the
/// perennial `MM-DD` range → the resolved `.reading.ja` / `.description.ja` values are
/// host-rendered to a PNG via `ImageRenderer`.
///
/// Why a harness card and not the production `TodayView`: `TodayView` gates its content
/// behind `@State hasAppeared` (it fades in via `onAppear`), and `ImageRenderer` never
/// fires `onAppear`, so host-rendering `TodayView` directly yields a blank canvas. The
/// harness renders the same resolved fields the production screen shows — the migration's
/// observable output — using the real resolved data, mirroring the established host-render
/// pattern in `AlmanacContentValidationTests`. The production `TodayView` itself is covered
/// end-to-end by the launched-app `TodayScreenUITests` / `ReadingDescriptionUITests`.
final class C2MigrationScreenshotTests: XCTestCase {

    /// Builds a UTC date in 2026 (the year is the daily-map lookup key now).
    private func date2026(month: Int, day: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var comps = DateComponents()
        comps.year = 2026
        comps.month = month
        comps.day = day
        comps.hour = 12
        return cal.date(from: comps)!
    }

    func testTodayContentRendersFromMigratedManifest() async throws {
        // Stage 1 (non-MainActor): real source → decode → resolve.
        let source = BundledContentSource()
        let manifest = try await source.load()

        let pinned = date2026(month: 6, day: 12)
        let resolved = try XCTUnwrap(
            TodayResolver.resolve(date: pinned, manifest: manifest),
            "TodayResolver must resolve 2026-06-12 against the migrated bundled manifest"
        )
        let positions = try XCTUnwrap(
            AlmanacResolver.resolve(date: pinned, manifest: manifest),
            "AlmanacResolver must resolve 2026-06-12 against the migrated bundled manifest"
        )

        // The migration's observable contract: localized ja values, date-stamped description.
        XCTAssertFalse(resolved.kigoEntry.reading.ja.isEmpty, "Kigo reading.ja must be non-empty")
        XCTAssertTrue(
            resolved.kigoEntry.description.ja.contains("2026-06-12"),
            "Resolved description.ja must carry its absolute date stamp"
        )
        XCTAssertFalse(resolved.ko.reading.ja.isEmpty, "Kō reading.ja must be non-empty")
        XCTAssertFalse(resolved.sekki.reading.ja.isEmpty, "Sekki reading.ja must be non-empty")

        // Stage 2 (MainActor): host-render the resolved content to PNG.
        let pngData: Data? = await MainActor.run {
            let card = ResolvedDayCardView(
                resolved: resolved,
                positions: positions,
                dateKey: "2026-06-12"
            )
            let renderer = ImageRenderer(content: card.frame(width: 340, height: 460))
            renderer.scale = 2.0
            return renderer.uiImage?.pngData()
        }

        let png = try XCTUnwrap(pngData, "ImageRenderer must produce PNG data for the resolved-day card")
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "c2-today-2026-06-12.png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

// MARK: - ResolvedDayCardView
//
// A throwaway host-render harness (NOT a shipped surface) that displays the same resolved
// fields the production Today screen shows — Kigo kanji/reading/description and the current
// Kō/Sekki readings — all read from the real resolved `ResolvedDay`/`AlmanacPositions`.

private struct ResolvedDayCardView: View {
    let resolved: ResolvedDay
    let positions: AlmanacPositions
    let dateKey: String

    var body: some View {
        VStack(spacing: 14) {
            Text(dateKey)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(resolved.kigoEntry.kanji)
                .font(.system(size: 48, weight: .bold))
            Text(resolved.kigoEntry.reading.ja)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(resolved.kigoEntry.description.ja)
                .font(.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack(spacing: 6) {
                Text(resolved.ko.kanji).font(.headline)
                Text(resolved.ko.reading.ja).font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Text(resolved.sekki.kanji).font(.subheadline)
                Text(resolved.sekki.reading.ja).font(.caption).foregroundStyle(.secondary)
            }
            Text("Kō \(positions.koYearPosition) / \(positions.koYearTotal)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
