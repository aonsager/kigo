import XCTest
import SwiftUI
@testable import Kigo

// MARK: - AlmanacContentValidationTests
//
// Slice #98 (C12): Verifies that all 24 Sekki loaded through BundledContentSource
// carry a non-empty Japanese gloss and a non-empty Japanese description.
//
// These tests exercise the PRODUCTION content path — no hand-built fixtures.
// The bundled manifest.json must be well-formed and contain the new required fields.

final class AlmanacContentValidationTests: XCTestCase {

    private func loadManifest() async throws -> Manifest {
        let source = BundledContentSource()
        return try await source.load()
    }

    // MARK: - AC1: All 24 Sekki have non-empty gloss (Japanese)

    /// BundledContentSource loads all 24 Sekki, each with a non-empty Japanese gloss.
    func testAllSekkiHaveNonEmptyJapaneseGloss() async throws {
        let manifest = try await loadManifest()
        XCTAssertEqual(manifest.sekki.count, 24,
                       "Manifest must have exactly 24 Sekki")
        for (index, sekki) in manifest.sekki.enumerated() {
            XCTAssertFalse(sekki.gloss.ja.isEmpty,
                           "Sekki at index \(index) (\(sekki.kanji)) has empty gloss.ja")
        }
    }

    // MARK: - AC1: All 24 Sekki have non-empty description (Japanese)

    /// BundledContentSource loads all 24 Sekki, each with a non-empty Japanese description.
    func testAllSekkiHaveNonEmptyJapaneseDescription() async throws {
        let manifest = try await loadManifest()
        XCTAssertEqual(manifest.sekki.count, 24,
                       "Manifest must have exactly 24 Sekki")
        for (index, sekki) in manifest.sekki.enumerated() {
            XCTAssertFalse(sekki.description.ja.isEmpty,
                           "Sekki at index \(index) (\(sekki.kanji)) has empty description.ja")
        }
    }

    // MARK: - AC3: schemaVersion is bumped from "1.0"

    /// The bundled manifest must carry a schemaVersion distinct from "1.0".
    func testSchemaVersionIsBumpedFrom1_0() async throws {
        let manifest = try await loadManifest()
        XCTAssertFalse(manifest.schemaVersion.isEmpty,
                       "schemaVersion must be non-empty")
        XCTAssertNotEqual(manifest.schemaVersion, "1.0",
                          "schemaVersion must be bumped beyond '1.0' after this slice")
    }

    // MARK: - Screenshot evidence: host-render Sekki gloss + description via ImageRenderer

    /// Loads the real bundled Manifest through BundledContentSource, picks the first Sekki
    /// (risshun), feeds its decoded gloss and description (Japanese) into a simple SwiftUI
    /// view, renders it to PNG via ImageRenderer, and attaches it with keepAlways lifetime.
    ///
    /// This is a host-render test (not a UI snapshot) — it proves the data path from
    /// BundledContentSource through the LocalizedText fields to a rendered pixel, using
    /// REAL bundled data (no fakes).
    ///
    /// @MainActor is required for ImageRenderer (Swift 6 concurrency).
    func testSekkiCardRendersRealData() async throws {
        // Stage 1 (non-MainActor): Load real manifest
        let manifest = try await loadManifest()

        // Pick risshun (first Sekki) if available, otherwise the first in the array
        let sekki = manifest.sekki.first(where: { $0.id == "risshun" })
                    ?? manifest.sekki.first

        guard let sekki else {
            XCTFail("Bundled manifest must have at least one Sekki")
            return
        }

        XCTAssertFalse(sekki.gloss.ja.isEmpty,
                       "Picked Sekki must have non-empty gloss.ja for screenshot rendering")
        XCTAssertFalse(sekki.description.ja.isEmpty,
                       "Picked Sekki must have non-empty description.ja for screenshot rendering")

        // Stage 2 (MainActor): Host-render via ImageRenderer
        let pngData: Data? = await MainActor.run {
            let view = SekkiCardView(sekki: sekki)
            let renderer = ImageRenderer(content: view.frame(width: 320, height: 200))
            renderer.scale = 2.0
            return renderer.uiImage?.pngData()
        }

        guard let pngData else {
            XCTFail("ImageRenderer failed to produce PNG data for SekkiCardView")
            return
        }

        // Attach to test report — this is the ONLY reliable channel under xcodebuild test
        let attachment = XCTAttachment(data: pngData, uniformTypeIdentifier: "public.png")
        attachment.name = "sekki-risshun-gloss-description.png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

// MARK: - SekkiCardView
//
// A throwaway SwiftUI view used ONLY as a host-render harness for the screenshot test.
// It renders a Sekki's kanji, gloss (Japanese), and description (Japanese).
// This is NOT a shipped UI surface — see slice requirements ("Out of scope").

private struct SekkiCardView: View {
    let sekki: Sekki

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(sekki.kanji)
                .font(.largeTitle)
                .fontWeight(.bold)
            Text(sekki.reading)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(sekki.gloss.ja)
                .font(.headline)
            Text(sekki.description.ja)
                .font(.body)
                .lineLimit(nil)
        }
        .padding()
        .background(Color(.systemBackground))
    }
}
