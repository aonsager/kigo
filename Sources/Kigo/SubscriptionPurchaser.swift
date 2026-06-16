import StoreKit
import Foundation

// MARK: - SubscriptionPurchaserCancellation

/// Sentinel error thrown by `SubscriptionPurchaser.purchase(_:)` when the user
/// cancels the purchase sheet. Callers (e.g. `PaywallModel.buy()`) catch this
/// specifically to distinguish a deliberate cancellation from an unexpected error,
/// and swallow it silently in both cases — but the type distinction lets the model
/// leave a diagnostic breadcrumb if needed in the future.
public struct SubscriptionPurchaserCancellation: Error, Sendable {}

// MARK: - SubscriptionPurchaser

/// The StoreKit purchase seam: initiates a subscription purchase for the given
/// product ID. This is the injection point that keeps `PaywallModel.buy()` logic
/// testable headlessly — tests inject a fake that either succeeds or throws
/// deterministically, so no `SKTestSession`, `storekitd`, or real App Store call
/// is needed on the gating test path (ADR 0009 / CLAUDE.md).
///
/// Conformers must be `Sendable` so they can be captured by `@MainActor` models.
public protocol SubscriptionPurchaser: Sendable {
    /// Initiates a purchase for the given product ID.
    ///
    /// - Throws: `SubscriptionPurchaserCancellation` if the user dismisses the
    ///   sheet, or another error for any other failure (network, App Store, etc.).
    func purchase(_ productID: String) async throws
}

// MARK: - StoreKitSubscriptionPurchaser (production)

/// Production purchaser: a thin pass-through over StoreKit 2's `Product.purchase()`.
///
/// Deliberately thin — the only logic is mapping `Product.PurchaseResult.userCancelled`
/// to `SubscriptionPurchaserCancellation` so callers need not import StoreKit to
/// recognise a cancellation. Correctness is apparent on inspection.
///
/// This adapter is never exercised on the headless test path (real `Product.purchase()`
/// presents a sheet and hangs under `xcodebuild` from the CLI — ADR 0009). It is
/// covered, if at all, by the J4 manual lane (`KigoStoreKitIntegrationTests`).
public struct StoreKitSubscriptionPurchaser: SubscriptionPurchaser {
    public init() {}

    public func purchase(_ productID: String) async throws {
        guard let product = try await Product.products(for: [productID]).first else {
            throw SubscriptionPurchaserError.productNotFound(productID)
        }
        let result = try await product.purchase()
        if case .userCancelled = result {
            throw SubscriptionPurchaserCancellation()
        }
        // `.success` and `.pending` are both treated as "not an error":
        // success means the transaction was verified; pending means it needs
        // Ask-to-Buy approval. The caller (`PaywallModel.buy()`) re-reads
        // entitlement via `refreshEntitlement()` after this returns, so a
        // pending purchase will simply leave isActive unchanged until the
        // approval lands and the app re-checks.
    }
}

// MARK: - SubscriptionPurchaserError

/// Non-cancellation errors from `StoreKitSubscriptionPurchaser`.
public enum SubscriptionPurchaserError: Error, Sendable {
    case productNotFound(String)
}
