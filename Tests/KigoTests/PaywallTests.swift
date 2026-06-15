import XCTest
@testable import Kigo

/// Tests for `PaywallModel` — the observable view model that wires the Paywall screen
/// to the entitlement engine.
///
/// All tests drive the model through **injected in-memory fakes** for both the
/// transaction source and the shared store, exactly as `EntitlementTests` does for
/// `EntitlementProvider` itself. There is no `SKTestSession`, no `buyProduct`, no
/// `Kigo.storekit` wiring, and no real StoreKit call — those paths hang under
/// `xcodebuild` from the CLI (ADR 0009 / CLAUDE.md).
@MainActor
final class PaywallTests: XCTestCase {

    private static let widgetProductID = "com.tomeitotameigo.kigo.widgets.monthly"

    // MARK: - Shared fakes (mirror the pattern in EntitlementTests)

    /// In-memory StoreKit seam: reports exactly the product IDs it was given.
    private struct FakeTransactionSource: EntitlementTransactionSource {
        let productIDs: Set<String>
        func activeProductIDs() async -> Set<String> { productIDs }
    }

    /// In-memory shared-store seam: captures the last value written by activation.
    private actor FakeSharedStore: EntitlementSharedStore {
        var isActive: Bool = false
        func setActive(_ value: Bool) { isActive = value }
    }

    // MARK: - Tracer bullet: model exposes product display info

    /// The Paywall model exposes the widget-access product ID so the view can
    /// present it. This is a pure property — no async call needed.
    func testModelExposesWidgetProductID() {
        let source = FakeTransactionSource(productIDs: [])
        let store = FakeSharedStore()
        let provider = EntitlementProvider(source: source, store: store)
        let model = PaywallModel(provider: provider)
        XCTAssertEqual(model.productID, Self.widgetProductID,
                       "model must expose the widget monthly product ID")
    }

    // MARK: - isActive reflects entitlement state

    /// After `loadState()`, `isActive` is `false` when the source reports no products.
    func testIsActiveFalseWhenNotEntitled() async {
        let source = FakeTransactionSource(productIDs: [])
        let store = FakeSharedStore()
        let provider = EntitlementProvider(source: source, store: store)
        let model = PaywallModel(provider: provider)

        await model.loadState()

        XCTAssertFalse(model.isActive,
                       "no entitlements → isActive is false")
    }

    /// After `loadState()`, `isActive` is `true` when the source reports the widget product.
    func testIsActiveTrueWhenEntitled() async {
        let source = FakeTransactionSource(productIDs: [Self.widgetProductID])
        let store = FakeSharedStore()
        let provider = EntitlementProvider(source: source, store: store)
        let model = PaywallModel(provider: provider)

        await model.loadState()

        XCTAssertTrue(model.isActive,
                      "widget product entitled → isActive is true")
    }

    // MARK: - Restore drives entitlement engine and reflects resulting state

    /// `restore()` invokes the entitlement engine's restore path and updates
    /// `isActive` to reflect the resulting state. This exercises criterion 2 of
    /// slice #48: the restore action is wired through the injected seam, not
    /// directly to StoreKit.
    func testRestoreUpdatesIsActiveTrueWhenSourceIsEntitled() async {
        // Arrange: source is entitled but model hasn't loaded yet → isActive starts false.
        let source = FakeTransactionSource(productIDs: [Self.widgetProductID])
        let store = FakeSharedStore()
        let provider = EntitlementProvider(source: source, store: store)
        let model = PaywallModel(provider: provider)

        XCTAssertFalse(model.isActive, "precondition: isActive is false before restore")

        // Act: user taps Restore.
        await model.restore()

        // Assert: model now reflects the entitled state.
        XCTAssertTrue(model.isActive,
                      "restore with entitled source → isActive becomes true")
    }

    /// `restore()` leaves `isActive` false when the source reports no products
    /// (subscription lapsed / wrong account).
    func testRestoreLeavesIsActiveFalseWhenSourceReportsNothing() async {
        // Even if the store had been set to true before, restore must correct it.
        let source = FakeTransactionSource(productIDs: [])
        let store = FakeSharedStore()
        let provider = EntitlementProvider(source: source, store: store)
        let model = PaywallModel(provider: provider)

        // Simulate a previously-active state that has since lapsed.
        await model.loadState()
        // (store.isActive is still false since source is empty, but the model
        //  starts false; we verify restore doesn't flip it incorrectly.)

        await model.restore()

        XCTAssertFalse(model.isActive,
                       "restore with no entitled products → isActive remains false")
    }

    /// `restore()` also writes the updated flag into the shared store, keeping
    /// the Widget Gate (C7) in sync — this mirrors the behaviour of
    /// `EntitlementProvider.restoreEntitlement()`.
    func testRestoreWritesActiveFlagToSharedStore() async {
        let source = FakeTransactionSource(productIDs: [Self.widgetProductID])
        let store = FakeSharedStore()
        let provider = EntitlementProvider(source: source, store: store)
        let model = PaywallModel(provider: provider)

        await model.restore()

        let storeFlag = await store.isActive
        XCTAssertTrue(storeFlag,
                      "restore with entitled source → shared store active flag is true")
    }

    // MARK: - Slice #86: offer-display seam

    /// AC3 (headless): PaywallModel fed an injected `OfferDisplay` exposes exactly the
    /// injected price string and a non-empty duration string.
    ///
    /// This test exercises the full injection chain:
    ///  1. A `FixedOfferDisplay` (equivalent to what `launchOfferDisplay` returns under
    ///     `KIGO_FAKE_PRICE=¥300`) is constructed with a known price.
    ///  2. `PaywallModel` is initialised with that offer display.
    ///  3. `model.price` must equal the injected price string.
    ///  4. `model.duration` must be non-empty.
    ///
    /// No StoreKit `Product`, no `storekitd`, no async — pure synchronous injection.
    func testModelExposesInjectedOfferDisplayPriceAndDuration() {
        let source = FakeTransactionSource(productIDs: [])
        let store = FakeSharedStore()
        let provider = EntitlementProvider(source: source, store: store)

        let injected = OfferDisplay(price: "¥300", duration: "1 month")
        let model = PaywallModel(provider: provider, offerDisplay: injected)

        XCTAssertEqual(model.price, "¥300",
                       "model.price must equal the injected price string")
        XCTAssertFalse(model.duration.isEmpty,
                       "model.duration must be non-empty")
    }

    /// launchOfferDisplay resolver: present KIGO_FAKE_PRICE → returns that price string.
    func testLaunchOfferDisplayReturnsFakePriceWhenEnvPresent() {
        let result = launchOfferDisplay(environment: ["KIGO_FAKE_PRICE": "¥300"])
        XCTAssertEqual(result.price, "¥300",
                       "resolver must return the KIGO_FAKE_PRICE value as the price")
        XCTAssertFalse(result.duration.isEmpty,
                       "resolver must return a non-empty duration when KIGO_FAKE_PRICE is set")
    }

    /// launchOfferDisplay resolver: absent KIGO_FAKE_PRICE → returns production path (non-empty strings).
    func testLaunchOfferDisplayReturnsProductionPathWhenEnvAbsent() {
        let result = launchOfferDisplay(environment: [:])
        // We don't assert a specific price (it's the production placeholder), but
        // both strings must be non-empty so the UI never shows blank text.
        XCTAssertFalse(result.price.isEmpty,
                       "production path must return a non-empty price string")
        XCTAssertFalse(result.duration.isEmpty,
                       "production path must return a non-empty duration string")
    }
}
