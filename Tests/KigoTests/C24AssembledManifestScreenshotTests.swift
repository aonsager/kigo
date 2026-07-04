@testable import KigoCore
import XCTest
import SwiftUI
@testable import Kigo

// MARK: - C24AssembledManifestScreenshotTests

/// Screenshot evidence for C24 slice 1 (#199, ADR 0022): proves the CSV-to-manifest
/// assembly pipeline's real output — not hand-built JSON — decodes and resolves
/// through the app's real day-resolution logic end to end.
///
/// `assembled-worked-example-manifest.json` (bundled into KigoTests, see
/// `project.yml`) is the literal, committed output of running
/// `scripts/content/assemble.py --csv content/kigo-2026.example.csv --out …`
/// against the bundled `Resources/manifest.json` — not synthesized by this test.
/// From there the path is fully real and mirrors `C2MigrationScreenshotTests`:
/// `JSONDecoder` decodes the assembled `Manifest` → `TodayResolver.resolve` looks up
/// the worked example's 2026-07-07 (七夕/Tanabata) entry by `DayKey.absolute` and the
/// Kō by the perennial `MM-DD` range → the resolved fields are host-rendered to a PNG
/// via `ImageRenderer`.
///
/// Uses the same harness-card approach as `C2MigrationScreenshotTests` (see that
/// file's doc comment for why: `TodayView` gates content behind `onAppear`, which
/// `ImageRenderer` never fires).
final class C24AssembledManifestScreenshotTests: XCTestCase {

    /// Builds a UTC date in 2026 (the year is the daily-map lookup key).
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

    func testResolvedDayRendersFromAssembledWorkedExampleManifest() async throws {
        // Stage 1 (non-MainActor): load the pipeline's real, committed output —
        // not hand-built JSON — and decode it exactly as BundledContentSource
        // decodes the shipped manifest.
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "assembled-worked-example-manifest", withExtension: "json"),
            "assembled-worked-example-manifest.json must be bundled into KigoTests"
        )
        let data = try Data(contentsOf: url)
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)

        // The assembler's contract: Ko/Sekki copied through, dailyMap only from the CSV.
        XCTAssertEqual(manifest.ko.count, 72, "assembler must copy the 72 Ko through untouched")
        XCTAssertEqual(manifest.sekki.count, 24, "assembler must copy the 24 Sekki through untouched")
        XCTAssertGreaterThanOrEqual(manifest.dailyMap.count, 8, "worked example needs >=8 rows")

        let pinned = date2026(month: 7, day: 7)
        let resolved = try XCTUnwrap(
            TodayResolver.resolve(date: pinned, manifest: manifest),
            "TodayResolver must resolve 2026-07-07 against the assembled manifest"
        )
        let positions = try XCTUnwrap(
            AlmanacResolver.resolve(date: pinned, manifest: manifest),
            "AlmanacResolver must resolve 2026-07-07 against the assembled manifest"
        )

        // The assembled content's observable contract: real bilingual text, no
        // leftover dummy-data date-stamp instrumentation.
        XCTAssertEqual(resolved.kigoEntry.kanji, "七夕")
        XCTAssertEqual(resolved.kigoEntry.reading.ja, "たなばた")
        XCTAssertFalse(resolved.kigoEntry.description.ja.isEmpty)
        let descriptionEn = try XCTUnwrap(resolved.kigoEntry.description.en)
        XCTAssertFalse(descriptionEn.isEmpty)
        let blob = resolved.kigoEntry.description.ja + descriptionEn
        XCTAssertNil(
            blob.range(of: #"\(20\d\d-\d\d-\d\d\)"#, options: .regularExpression),
            "resolved description must carry no leftover dummy date-stamp"
        )

        // Stage 2 (MainActor): host-render the resolved content to PNG.
        let pngData: Data? = await MainActor.run {
            let card = AssembledDayCardView(resolved: resolved, positions: positions, dateKey: "2026-07-07")
            let renderer = ImageRenderer(content: card.frame(width: 340, height: 460))
            renderer.scale = 2.0
            return renderer.uiImage?.pngData()
        }

        let png = try XCTUnwrap(pngData, "ImageRenderer must produce PNG data for the resolved-day card")
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "c24-assembled-2026-07-07.png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

// MARK: - AssembledDayCardView
//
// A throwaway host-render harness (NOT a shipped surface), mirroring
// C2MigrationScreenshotTests' ResolvedDayCardView — displays the same resolved
// fields the production Today screen shows, using the real resolved
// `ResolvedDay`/`AlmanacPositions` decoded from the assembler's output.

private struct AssembledDayCardView: View {
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
            if let descriptionEn = resolved.kigoEntry.description.en {
                Text(descriptionEn)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
