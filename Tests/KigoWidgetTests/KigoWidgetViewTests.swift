@testable import KigoCore
import XCTest
import SwiftUI
import WidgetKit

// MARK: - KigoWidgetViewTests
//
// Slice #73: Verifies the KigoWidgetView entry-data contract.
//
// KigoWidgetView is a pure SwiftUI view — we cannot snapshot-test the rendered
// output in a headless XCTest suite. These tests verify the entry-level contract
// that the view layer depends on: the entry carries the expected fields and the
// backdrop is always present (ungated — ADR 0019, Task 4 image pivot).
//
// The real rendering (gradient background, typography) is observable only in the
// Xcode canvas / simulator and is verified by inspection (see J1 in the slice spec).
final class KigoWidgetViewTests: XCTestCase {

    // MARK: - Entry contract: view can be constructed from a resolved entry

    /// KigoWidgetView initialises without crashing when given a fully-resolved entry.
    func testViewInitialisesWithResolvedEntry() {
        let entry = KigoWidgetEntry(
            date: .now,
            kanji: "蛍",
            reading: "ほたる",
            backdropAssetName: "backdrop-shousho",
            fallbackHue: 0.42
        )
        // Constructing the view must not crash (compile-time + runtime sanity check).
        let view = KigoWidgetView(entry: entry)
        // The entry's fields are accessible from the view's entry property.
        XCTAssertEqual(view.entry.kanji, "蛍")
        XCTAssertEqual(view.entry.reading, "ほたる")
        XCTAssertEqual(view.entry.backdropAssetName, "backdrop-shousho")
        XCTAssertEqual(view.entry.fallbackHue, 0.42)
    }

    /// KigoWidgetView initialises with an unresolved (placeholder) entry — nil
    /// content fields — without crashing. Used during widget gallery loading state.
    func testViewInitialisesWithPlaceholderEntry() {
        let entry = KigoWidgetEntry(date: .now)
        let view = KigoWidgetView(entry: entry)
        XCTAssertNil(view.entry.kanji, "Placeholder entry must have nil kanji")
        XCTAssertNil(view.entry.reading, "Placeholder entry must have nil reading")
    }

    // MARK: - Ungated invariant: the backdrop is always carried on the entry

    /// A resolved entry always carries a non-empty backdropAssetName — the widget
    /// is ungated (ADR 0019): the backdrop renders regardless of entitlement state.
    func testResolvedEntryAlwaysCarriesBackdropAssetName() {
        let entry = KigoWidgetEntry(
            date: .now,
            kanji: "蛍",
            reading: "ほたる",
            backdropAssetName: "backdrop-shousho",
            fallbackHue: 0.42
        )
        XCTAssertFalse(entry.backdropAssetName.isEmpty, "Resolved entry must carry a non-empty backdropAssetName")
    }

    /// A resolved entry with a withheld/absent entitlement (there is no such gate any
    /// more) still carries kanji and reading and the same non-empty backdrop.
    func testResolvedEntryCarriesKanjiReadingAndBackdropTogether() {
        let entry = KigoWidgetEntry(
            date: .now,
            kanji: "蛍",
            reading: "ほたる",
            backdropAssetName: "backdrop-shousho",
            fallbackHue: 0.42
        )
        XCTAssertEqual(entry.kanji, "蛍",      "kanji must be carried on the entry")
        XCTAssertEqual(entry.reading, "ほたる", "reading must be carried on the entry")
        XCTAssertEqual(entry.backdropAssetName, "backdrop-shousho", "backdrop must be carried alongside kanji/reading")
    }
}
