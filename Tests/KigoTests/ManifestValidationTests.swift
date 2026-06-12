import XCTest
@testable import Kigo

final class ManifestValidationTests: XCTestCase {

    /// Loads the bundled manifest.json from the app bundle (Bundle.main, since KigoTests
    /// runs hosted in the Kigo app) and decodes it into the typed Manifest value type.
    /// This proves: committed JSON → bundled resource → decoded at runtime → typed content.
    func testBundledManifestDecodesWithNonEmptySchemaVersion() throws {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "manifest", withExtension: "json"),
            "manifest.json must be bundled in the Kigo app target — check project.yml resources"
        )
        let data = try Data(contentsOf: url)
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        XCTAssertFalse(
            manifest.schemaVersion.isEmpty,
            "Decoded Manifest must carry a non-empty schemaVersion"
        )
    }
}
