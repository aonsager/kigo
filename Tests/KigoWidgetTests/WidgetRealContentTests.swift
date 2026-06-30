import XCTest
import SwiftUI

// MARK: - WidgetRealContentTests
//
// Slice #81: Real end-to-end content path — BundledContentSource drives the widget entry.
//
// Unlike WidgetTimelineTests (which injects a hand-built minimal Manifest), this suite
// exercises the PRODUCTION content path: it constructs BundledContentSource() with no
// arguments, awaits load() to decode the real bundled manifest.json, picks an MM-DD key
// actually present in that loaded manifest, injects a FixedDateProvider pinned to that
// date, builds the entry via WidgetTimelineBuilder, and asserts the entry's kanji and
// reading equal the values read from the very same loaded manifest's daily-map.
//
// This proves that:
// 1. manifest.json is bundled into the KigoWidgetTests bundle (AC1).
// 2. BundledContentSource().load() decodes it without error (AC3).
// 3. WidgetTimelineBuilder produces an entry whose fields match the manifest (AC3).
// 4. No hand-built fixture is used anywhere in the data path (AC3).
//
// The contrast with WidgetTimelineTests is intentional and is the point of this slice.
final class WidgetRealContentTests: XCTestCase {

    // MARK: - AC1 + AC3: BundledContentSource resolves manifest.json from the test bundle

    /// BundledContentSource().load() decodes the real bundled manifest without error.
    /// The manifest must be non-trivial: it must have at least one dailyMap entry.
    func testBundledContentSourceLoadsRealManifest() async throws {
        let source = BundledContentSource()
        let manifest = try await source.load()

        XCTAssertFalse(manifest.dailyMap.isEmpty,
                       "Real manifest must have at least one dailyMap entry")
        XCTAssertFalse(manifest.ko.isEmpty,
                       "Real manifest must have at least one Ko entry")
        XCTAssertFalse(manifest.sekki.isEmpty,
                       "Real manifest must have at least one Sekki entry")
    }

    // MARK: - AC3: WidgetTimelineBuilder entry matches the real manifest for a pinned date

    /// Loads the real manifest via BundledContentSource(), picks the first available
    /// MM-DD key, pins a FixedDateProvider to that date, builds the entry, and asserts
    /// the entry's kanji and reading equal the manifest's daily-map values for that key.
    ///
    /// The assertion can NEVER pass vacuously against a hand-built fixture because:
    /// - the expected values are read from `manifest.dailyMap[pickedKey]` (the same
    ///   real manifest that the builder was given)
    /// - the builder is constructed with `manifest` as injected, not with a fake
    func testBuilderEntryMatchesRealManifestForPinnedDate() async throws {
        // Step 1: Load the real bundled manifest — no injection.
        let source = BundledContentSource()
        let manifest = try await source.load()

        // Step 2: Pick the first absolute 2026-MM-DD key present in the loaded manifest.
        // Sort for determinism; any key that exists in the manifest is valid.
        let sortedKeys = manifest.dailyMap.keys.sorted()
        guard let pickedKey = sortedKeys.first,
              let expectedEntry = manifest.dailyMap[pickedKey] else {
            XCTFail("Real manifest must have at least one dailyMap entry to pick a key")
            return
        }

        // Step 3: Parse the absolute YYYY-MM-DD key into year/month/day integers.
        let parts = pickedKey.split(separator: "-")
        XCTAssertEqual(parts.count, 3, "Absolute key must have exactly three components")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            XCTFail("Could not parse YYYY-MM-DD key '\(pickedKey)' into year/month/day integers")
            return
        }

        // Step 4: Build a UTC Date pinned to that absolute date (the year is the lookup key now).
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        comps.minute = 0
        comps.second = 0
        guard let pinnedDate = cal.date(from: comps) else {
            XCTFail("Could not construct a Date from MM-DD key '\(pickedKey)'")
            return
        }

        // Step 5: Build the widget entry via WidgetTimelineBuilder — real manifest, real date seam.
        let provider = FixedDateProvider(date: pinnedDate)
        let builder = WidgetTimelineBuilder(dateProvider: provider, manifest: manifest)
        let entry = builder.buildEntry()

        // Step 6: Assert entry fields match the manifest's dailyMap for the picked key.
        XCTAssertNotNil(entry,
                        "Builder must return a non-nil entry for key '\(pickedKey)' present in the real manifest")
        XCTAssertEqual(entry?.kanji, expectedEntry.kanji,
                       "Entry kanji must equal manifest dailyMap[\(pickedKey)].kanji")
        XCTAssertEqual(entry?.reading, expectedEntry.reading.ja,
                       "Entry reading must equal manifest dailyMap[\(pickedKey)].reading.ja")
    }

    // MARK: - Screenshot evidence: host-render the real KigoWidgetView

    /// Produces a host-rendered PNG of KigoWidgetView driven by the real BundledContentSource
    /// manifest and the real WidgetTimelineBuilder entry for the pinned date.
    ///
    /// Per the unscreenshottable-surfaces catalog (rung 2): the widget surface itself can't
    /// be driven headlessly, but the production view + production data path CAN be host-rendered
    /// here and saved to disk as evidence. No hand-built fixture is used anywhere.
    ///
    /// The image is saved to the test's attachments AND to disk at a deterministic path so
    /// the afk-loop can find it.
    ///
    /// @MainActor is required because ImageRenderer, KigoWidgetView, and UIImage.pngData()
    /// are all MainActor-bound in Swift 6. The async manifest load and builder call must
    /// be done before entering MainActor context, so we split them into two stages.
    func testHostRenderRealWidgetView() async throws {
        // Stage 1 (non-MainActor): Load real manifest and build the widget entry.
        let source = BundledContentSource()
        let manifest = try await source.load()

        // Pick "2026-01-01" if present, otherwise the first sorted key — deterministic choice.
        let targetKey = manifest.dailyMap["2026-01-01"] != nil ? "2026-01-01" : manifest.dailyMap.keys.sorted().first!
        guard let expectedEntry = manifest.dailyMap[targetKey] else {
            XCTFail("No entry for key '\(targetKey)' in real manifest")
            return
        }

        // Build date for the chosen absolute YYYY-MM-DD key.
        let parts = targetKey.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            XCTFail("Could not parse key '\(targetKey)'")
            return
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        comps.minute = 0
        comps.second = 0
        let pinnedDate = cal.date(from: comps)!

        // Build entry via real WidgetTimelineBuilder + real manifest
        let provider = FixedDateProvider(date: pinnedDate)
        let builder = WidgetTimelineBuilder(dateProvider: provider, manifest: manifest)
        let widgetEntry = builder.buildEntry()

        guard let widgetEntry else {
            XCTFail("Builder returned nil for key '\(targetKey)' — cannot host-render")
            return
        }

        // Verify the entry matches the expected manifest values before rendering
        XCTAssertEqual(widgetEntry.kanji, expectedEntry.kanji)
        XCTAssertEqual(widgetEntry.reading, expectedEntry.reading.ja)

        // Stage 2 (MainActor): Host-render the real KigoWidgetView driven by the real entry.
        // ImageRenderer, KigoWidgetView init, and UIImage.pngData() are all @MainActor.
        //
        // Write to the host-side worktree root via the absolute source path. The path is
        // constructed at compile time using #file so it works both in the simulator and on
        // the host — the simulator maps host absolute paths to the same absolute path on
        // the host filesystem when writing files.
        let screenshotURL = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()  // WidgetRealContentTests.swift → KigoWidgetTests/
            .deletingLastPathComponent()  // KigoWidgetTests/ → Tests/
            .deletingLastPathComponent()  // Tests/ → worktree root
            .appendingPathComponent("widget-real-content-screenshot.png")

        let pngData: Data? = await MainActor.run {
            let view = KigoWidgetView(entry: widgetEntry)
            let renderer = ImageRenderer(content: view.frame(width: 169, height: 169))
            renderer.scale = 2.0
            return renderer.uiImage?.pngData()
        }

        guard let pngData else {
            XCTFail("ImageRenderer failed to produce PNG data for KigoWidgetView")
            return
        }

        try pngData.write(to: screenshotURL)

        // Attach to test report for Xcode / CI visibility
        let attachment = XCTAttachment(data: pngData, uniformTypeIdentifier: "public.png")
        attachment.name = "KigoWidgetView-real-content-\(targetKey).png"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Confirm the screenshot was written
        XCTAssertTrue(FileManager.default.fileExists(atPath: screenshotURL.path),
                      "Screenshot must be written to \(screenshotURL.path)")
    }
}
