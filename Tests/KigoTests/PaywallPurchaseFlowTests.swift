import XCTest
import SwiftUI
@testable import Kigo

/// Tests for `PaywallModel.buy()` — the purchase action that calls through the
/// injected `SubscriptionPurchaser` seam, then refreshes entitlement state.
///
/// All tests drive the model through **injected in-memory fakes** for both the
/// purchaser and the entitlement engine. There is no `SKTestSession`, no real
/// `Product.purchase()`, and no `storekitd` call on this path — following the same
/// pattern as `PaywallTests` and ADR 0009 / CLAUDE.md. The production
/// `StoreKitSubscriptionPurchaser` is a thin pass-through, correct by inspection.
@MainActor
final class PaywallPurchaseFlowTests: XCTestCase {

    private static let widgetProductID = "com.tomeitotameigo.kigo.widgets.monthly"

    // MARK: - Shared fakes

    /// In-memory StoreKit seam: initially empty; can be mutated between arrange and act.
    private actor FakeTransactionSource: EntitlementTransactionSource {
        var productIDs: Set<String> = []
        func activeProductIDs() async -> Set<String> { productIDs }
        func seed(_ ids: Set<String>) { productIDs = ids }
    }

    /// In-memory shared-store seam: captures the last value written by activation.
    private actor FakeSharedStore: EntitlementSharedStore {
        var isActive: Bool = false
        func setActive(_ value: Bool) { isActive = value }
    }

    /// In-memory purchaser: configured to either succeed or throw on `purchase(_:)`.
    private actor FakeSubscriptionPurchaser: SubscriptionPurchaser {
        enum Behaviour {
            case succeed
            case throwError(Error)
        }
        private var behaviour: Behaviour = .succeed
        func setBehaviour(_ b: Behaviour) { behaviour = b }
        func purchase(_ productID: String) async throws {
            switch behaviour {
            case .succeed: return
            case .throwError(let e): throw e
            }
        }
    }

    // MARK: - Tracer bullet: buy() succeeds, model.isActive becomes true

    /// Success path: purchaser succeeds, source is pre-seeded with the widget product.
    /// After `buy()`, `model.isActive` is `true` and the shared store flag is `true`.
    func testBuySuccessSetIsActiveTrue() async {
        // Arrange
        let source = FakeTransactionSource()
        let store = FakeSharedStore()
        let purchaser = FakeSubscriptionPurchaser()

        // Pre-seed the source so that after purchase the entitlement check succeeds.
        await source.seed([Self.widgetProductID])

        let provider = EntitlementProvider(source: source, store: store)
        let model = PaywallModel(provider: provider, purchaser: purchaser)

        XCTAssertFalse(model.isActive, "precondition: isActive starts false")

        // Act
        await model.buy()

        // Assert: model reflects entitlement
        XCTAssertTrue(model.isActive,
                      "buy() with succeeding purchaser and entitled source → isActive is true")

        // Assert: shared store updated
        let storeFlag = await store.isActive
        XCTAssertTrue(storeFlag,
                      "buy() with succeeding purchaser → shared store isActive flag is true")
    }

    // MARK: - Cancelled: user cancels, isActive stays false

    /// Cancellation sentinel path: purchaser throws the cancellation sentinel.
    /// After `buy()`, `model.isActive` is `false` and no error propagates.
    func testBuyCancelledLeavesIsActiveFalse() async {
        // Arrange
        let source = FakeTransactionSource()
        let store = FakeSharedStore()
        let purchaser = FakeSubscriptionPurchaser()

        await purchaser.setBehaviour(.throwError(SubscriptionPurchaserCancellation()))

        let provider = EntitlementProvider(source: source, store: store)
        let model = PaywallModel(provider: provider, purchaser: purchaser)

        // Act (must not throw)
        await model.buy()

        // Assert
        XCTAssertFalse(model.isActive,
                       "buy() cancelled → isActive remains false")

        let storeFlag = await store.isActive
        XCTAssertFalse(storeFlag,
                       "buy() cancelled → shared store isActive flag remains false")
    }

    // MARK: - Failed: non-cancellation error, no crash

    /// Non-cancellation error path: purchaser throws an arbitrary error.
    /// After `buy()`, `model.isActive` is `false` and no crash occurs.
    func testBuyFailedLeavesIsActiveFalse() async {
        // Arrange
        struct ArbitraryError: Error {}
        let source = FakeTransactionSource()
        let store = FakeSharedStore()
        let purchaser = FakeSubscriptionPurchaser()

        await purchaser.setBehaviour(.throwError(ArbitraryError()))

        let provider = EntitlementProvider(source: source, store: store)
        let model = PaywallModel(provider: provider, purchaser: purchaser)

        // Act (must not throw / crash)
        await model.buy()

        // Assert
        XCTAssertFalse(model.isActive,
                       "buy() with non-cancellation error → isActive remains false, no crash")
    }

    // MARK: - Screenshot evidence

    /// Produces a host-rendered screenshot of `PaywallView` with `isActive == true`
    /// (produced by calling `buy()` on a model with a succeeding fake purchaser),
    /// showing the `paywall.manage` surface. Emitted as XCTAttachment with
    /// `.keepAlways` lifetime and stable name `slice-116-paywall-manage`.
    func testScreenshotPaywallManageSurface() async throws {
        // Arrange: same setup as the success test
        let source = FakeTransactionSource()
        let store = FakeSharedStore()
        let purchaser = FakeSubscriptionPurchaser()
        await source.seed([Self.widgetProductID])

        let provider = EntitlementProvider(source: source, store: store)
        let model = PaywallModel(provider: provider, purchaser: purchaser)

        // Act: drive buy() to make isActive == true
        await model.buy()
        XCTAssertTrue(model.isActive, "precondition: isActive is true before screenshot")

        // Render PaywallView with the active model
        let view = PaywallView(model: model)
        let renderer = ImageRenderer(content: view.frame(width: 390, height: 844))
        renderer.scale = 2.0

        guard let uiImage = renderer.uiImage else {
            XCTFail("ImageRenderer failed to produce a UIImage")
            return
        }

        // Emit as XCTAttachment with .keepAlways lifetime
        let attachment = XCTAttachment(image: uiImage)
        attachment.name = "slice-116-paywall-manage"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
