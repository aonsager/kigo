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

    // MARK: - Shared store activation (slice #46)

    /// In-memory shared-store seam: captures the last value written by activation.
    private actor FakeSharedStore: EntitlementSharedStore {
        var isActive: Bool = false
        func setActive(_ value: Bool) { isActive = value }
    }

    func testActivationWritesTrueWhenWidgetProductEntitled() async {
        let source = FakeTransactionSource(productIDs: [Self.widgetProductID])
        let store = FakeSharedStore()
        let provider = EntitlementProvider(source: source, store: store)
        await provider.refreshEntitlement()
        let flag = await store.isActive
        XCTAssertTrue(flag, "widget product entitled → shared store active flag is true")
    }

    func testActivationWritesFalseWhenNoProductsEntitled() async {
        let source = FakeTransactionSource(productIDs: [])
        let store = FakeSharedStore()
        let provider = EntitlementProvider(source: source, store: store)
        await provider.refreshEntitlement()
        let flag = await store.isActive
        XCTAssertFalse(flag, "no entitlements → shared store active flag is false")
    }

    // MARK: - Restore (slice #47)

    func testRestoreReEstablishesActiveFlagAfterStoreClear() async {
        // Arrange: source is entitled; activate to write true into the store.
        let source = FakeTransactionSource(productIDs: [Self.widgetProductID])
        let store = FakeSharedStore()
        let provider = EntitlementProvider(source: source, store: store)
        await provider.refreshEntitlement()

        // Simulate a cleared store (fresh install / "Restore" before restore runs).
        await store.setActive(false)
        let clearedFlag = await store.isActive
        XCTAssertFalse(clearedFlag, "precondition: flag is false after clear")

        // Act: restore re-reads the still-entitled source and re-writes the flag.
        await provider.restoreEntitlement()

        // Assert: flag is true again — rebuilt purely from source + shared-store seam.
        let restoredFlag = await store.isActive
        XCTAssertTrue(restoredFlag, "restore with entitled source → active flag is true")
    }

    func testRestoreLeavesActiveFalseWhenSourceReportsNothing() async {
        // Source reports no products (e.g. subscription lapsed / wrong account).
        let source = FakeTransactionSource(productIDs: [])
        let store = FakeSharedStore()
        let provider = EntitlementProvider(source: source, store: store)

        // Even if the store somehow has true already, restore should correct it.
        await store.setActive(true)

        await provider.restoreEntitlement()

        let flag = await store.isActive
        XCTAssertFalse(flag, "restore with no entitled products → active flag is false")
    }
}
