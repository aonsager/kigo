import XCTest
import StoreKit
import StoreKitTest
@testable import Kigo

/// Real-StoreKit integration test — the **J4 manual lane** (ADR 0009).
///
/// This is the one place the *production* StoreKit adapters
/// (`StoreKitTransactionSource` reading `Transaction.currentEntitlements`, and the
/// real StoreKit 2 product-loading path) are exercised end-to-end against a real —
/// but local, free — `storekitd` driven by `SKTestSession`. The headless gating
/// suites (C6/C9/C10) instead inject in-memory fakes; this target proves the thin
/// adapters those fakes stand in for are actually correct.
///
/// It is fenced **off** the autonomous loop two ways:
///
///  1. It is **not** a target of the `Kigo` scheme's test action, so the canonical
///     `xcodebuild test -scheme Kigo …` loop invocation never builds or runs it.
///  2. Every test self-skips unless `KIGO_RUN_STOREKIT_INTEGRATION=1` is set — which
///     only the `KigoStoreKitIntegrationTests` scheme's test action sets. So if this
///     target were ever pulled onto a headless path without that variable, it skips
///     *before* touching StoreKit and cannot hang the loop.
///
/// Run it intentionally from Xcode: pick the `KigoStoreKitIntegrationTests` scheme
/// and press **Cmd+U**. `SKTestSession` only works through the IDE launch path; from
/// the public CLI it errors (`SKInternalErrorDomain Code=3`) or hangs indefinitely
/// (ADR 0009 / CLAUDE.md). Do not add this target to the `Kigo` scheme, and do not
/// run this scheme via `xcodebuild test` from the CLI.
final class EntitlementStoreKitIntegrationTests: XCTestCase {

    /// Gate: only proceed in the opted-in IDE lane. Keep this the first line of
    /// every test so no StoreKit call can run on a headless/CLI path.
    private func requireIDELane() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KIGO_RUN_STOREKIT_INTEGRATION"] == "1",
            """
            SKTestSession integration test skipped on the headless/CLI path. \
            Run via the KigoStoreKitIntegrationTests scheme in Xcode (Cmd+U). See ADR 0009.
            """
        )
    }

    /// A real test purchase, driven through `storekitd`, makes the **production**
    /// `StoreKitTransactionSource` report the widget-access product as entitled —
    /// proving the `Transaction.currentEntitlements` adapter the unit tests stub out
    /// (C6/C10) is actually correct end-to-end.
    func testRealPurchaseEntitlesProductionTransactionSource() async throws {
        try requireIDELane()

        let session = try SKTestSession(configurationFileNamed: "Products")
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }

        let productID = EntitlementProvider.widgetMonthlyProductID
        let source = StoreKitTransactionSource()

        // Before any purchase, the production adapter reports no entitlement.
        let before = await source.activeProductIDs()
        XCTAssertFalse(before.contains(productID), "no entitlement before purchase")

        // Drive a real (test) purchase through storekitd.
        _ = try await session.buyProduct(identifier: productID)

        // The production adapter now reflects the entitlement.
        let after = await source.activeProductIDs()
        XCTAssertTrue(
            after.contains(productID),
            "production StoreKitTransactionSource reflects the test purchase"
        )
    }

    /// The product configured in `Products.storekit` loads through the **real**
    /// StoreKit 2 product-loading path with the expected id and a monthly period —
    /// the path the Paywall's offer-display seam stubs out for C9.
    func testWidgetAccessProductLoadsFromStoreKit() async throws {
        try requireIDELane()

        let session = try SKTestSession(configurationFileNamed: "Products")
        session.disableDialogs = true
        defer { session.clearTransactions() }

        let productID = EntitlementProvider.widgetMonthlyProductID
        let products = try await Product.products(for: [productID])
        let product = try XCTUnwrap(
            products.first,
            "widget-access product loads from the local test config"
        )

        XCTAssertEqual(product.id, productID)
        XCTAssertEqual(product.subscription?.subscriptionPeriod.unit, .month)
        XCTAssertEqual(product.subscription?.subscriptionPeriod.value, 1)
    }
}
