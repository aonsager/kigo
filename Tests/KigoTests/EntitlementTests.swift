import XCTest
@testable import Kigo

/// Tests for `EntitlementProvider` — the seam that derives subscription entitlement
/// state from a StoreKit transaction source.
///
/// These drive the provider through an **injected in-memory source**, not
/// `SKTestSession`: the logic (active/inactive derivation) is what C6 gates on, and
/// it must run headless, deterministically, and fast. Driving a real purchase through
/// `SKTestSession` hangs under `xcodebuild` from the CLI (ADR 0009 / CLAUDE.md), so it
/// is kept off this gating path. The production `StoreKitTransactionSource` is a thin
/// pass-through, correct by inspection.
final class EntitlementTests: XCTestCase {

    private static let widgetProductID = "com.tomeitotameigo.kigo.widgets.monthly"

    /// In-memory StoreKit seam: reports exactly the product IDs it was given.
    private struct FakeTransactionSource: EntitlementTransactionSource {
        let productIDs: Set<String>
        func activeProductIDs() async -> Set<String> { productIDs }
    }

    func testEntitlementInactiveWhenSourceReportsNothing() async {
        let provider = EntitlementProvider(source: FakeTransactionSource(productIDs: []))
        let isActive = await provider.isEntitlementActive()
        XCTAssertFalse(isActive, "no entitlements → inactive")
    }

    func testEntitlementActiveWhenSourceReportsWidgetProduct() async {
        let provider = EntitlementProvider(
            source: FakeTransactionSource(productIDs: [Self.widgetProductID])
        )
        let isActive = await provider.isEntitlementActive()
        XCTAssertTrue(isActive, "widget product entitled → active")
    }

    func testEntitlementInactiveForUnrelatedProductOnly() async {
        let provider = EntitlementProvider(
            source: FakeTransactionSource(productIDs: ["com.tomeitotameigo.kigo.unrelated"])
        )
        let isActive = await provider.isEntitlementActive()
        XCTAssertFalse(isActive, "only an unrelated product entitled → inactive")
    }
}
