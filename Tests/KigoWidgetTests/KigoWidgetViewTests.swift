import XCTest
import SwiftUI
import WidgetKit

// MARK: - KigoWidgetViewTests
//
// Slice #73: Verifies the KigoWidgetView entry-data contract.
//
// KigoWidgetView is a pure SwiftUI view — we cannot snapshot-test the rendered
// output in a headless XCTest suite. These tests verify the entry-level contract
// that the view layer depends on: that the entry carries the expected fields
// and that the showsImage flag correctly gates image rendering.
//
// The real rendering (gradient background, typography) is observable only in the
// Xcode canvas / simulator and is verified by inspection (see J1 in the slice spec).
final class KigoWidgetViewTests: XCTestCase {

    // MARK: - Entry contract: view can be constructed from a resolved entry

    /// KigoWidgetView initialises without crashing when given a fully-resolved
    /// entry with showsImage == true (active entitlement path).
    func testViewInitialisesWithResolvedEntryAndActiveEntitlement() {
        let entry = KigoWidgetEntry(
            date: .now,
            kanji: "蛍",
            reading: "ほたる",
            imageId: "img-firefly",
            showsImage: true
        )
        // Constructing the view must not crash (compile-time + runtime sanity check).
        let view = KigoWidgetView(entry: entry)
        // The entry's fields are accessible from the view's entry property.
        XCTAssertEqual(view.entry.kanji, "蛍")
        XCTAssertEqual(view.entry.reading, "ほたる")
        XCTAssertEqual(view.entry.imageId, "img-firefly")
        XCTAssertTrue(view.entry.showsImage, "showsImage must be true for active entitlement")
    }

    /// KigoWidgetView initialises without crashing when given a resolved entry
    /// with showsImage == false (inactive entitlement path — image withheld).
    func testViewInitialisesWithResolvedEntryAndInactiveEntitlement() {
        let entry = KigoWidgetEntry(
            date: .now,
            kanji: "天の川",
            reading: "あまのがわ",
            imageId: "img-milky",
            showsImage: false
        )
        let view = KigoWidgetView(entry: entry)
        XCTAssertEqual(view.entry.kanji, "天の川")
        XCTAssertEqual(view.entry.reading, "あまのがわ")
        XCTAssertFalse(view.entry.showsImage, "showsImage must be false for inactive entitlement")
    }

    /// KigoWidgetView initialises with an unresolved (placeholder) entry — nil
    /// content fields — without crashing. Used during widget gallery loading state.
    func testViewInitialisesWithPlaceholderEntry() {
        let entry = KigoWidgetEntry(date: .now)
        let view = KigoWidgetView(entry: entry)
        XCTAssertNil(view.entry.kanji, "Placeholder entry must have nil kanji")
        XCTAssertNil(view.entry.reading, "Placeholder entry must have nil reading")
        XCTAssertFalse(view.entry.showsImage, "Placeholder entry must not show image")
    }

    // MARK: - showsImage gates image rendering: entry-level contract

    /// Entry with showsImage == true carries a non-nil imageId (the image
    /// layer is only rendered when both conditions hold: showsImage AND imageId != nil).
    func testActiveEntitlementEntryCarriesNonNilImageId() {
        let entry = KigoWidgetEntry(
            date: .now,
            kanji: "蛍",
            reading: "ほたる",
            imageId: "img-firefly",
            showsImage: true
        )
        XCTAssertNotNil(entry.imageId, "Active entitlement entry must carry a non-nil imageId")
    }

    /// Entry with showsImage == false still carries kanji and reading
    /// (the text content is never withheld, only the image).
    func testInactiveEntitlementEntryCarriesKanjiAndReading() {
        let entry = KigoWidgetEntry(
            date: .now,
            kanji: "蛍",
            reading: "ほたる",
            imageId: "img-firefly",
            showsImage: false
        )
        XCTAssertEqual(entry.kanji, "蛍",      "kanji must be carried even without image entitlement")
        XCTAssertEqual(entry.reading, "ほたる", "reading must be carried even without image entitlement")
    }
}
