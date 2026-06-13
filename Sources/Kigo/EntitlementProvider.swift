import StoreKit

// MARK: - EntitlementProvider

/// Derives subscription entitlement state from StoreKit's verified transactions.
///
/// This is the seam that owns StoreKit interaction for entitlement checking (ADR 0009).
/// It exposes a simple `isEntitlementActive()` check: the caller does not need to
/// understand StoreKit transaction types, verification, or subscription groups.
///
/// Concurrency: the check is `async` because StoreKit's `Transaction.currentEntitlements`
/// is an `AsyncSequence`. Swift 6 strict concurrency is satisfied — `EntitlementProvider`
/// itself is `Sendable` because it holds no mutable state.
public struct EntitlementProvider: Sendable {

    /// The product ID for the widget-access monthly subscription.
    private static let widgetMonthlyProductID = "com.tomeitotameigo.kigo.widgets.monthly"

    public init() {}

    // MARK: - Entitlement check

    /// Returns `true` if the user holds an active, verified entitlement for the
    /// widget-access subscription; `false` otherwise (no purchase, expired, or revoked).
    ///
    /// Iterates `Transaction.currentEntitlements` — StoreKit's authoritative list of
    /// transactions that currently entitle the user to content. An empty sequence (no
    /// purchases) or a sequence with no matching verified transaction yields `false`.
    public func isEntitlementActive() async -> Bool {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.widgetMonthlyProductID {
                return true
            }
        }
        return false
    }
}
