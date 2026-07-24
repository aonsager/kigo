import KigoCore
import StoreKit
import Foundation

// MARK: - StoreKitTransactionSource (production)
// The `EntitlementTransactionSource` protocol and `EntitlementProvider` logic
// live in KigoCore (StoreKit-free, tested host-side). This file is the app-side
// StoreKit half: the production conformance plus the zero-argument production
// convenience initializer.

/// Production source: derives entitled product IDs from StoreKit 2's authoritative
/// `Transaction.currentEntitlements`. Deliberately thin — a pass-through that is
/// correct by inspection — because it cannot be exercised on the headless test path
/// (real StoreKit purchases hang under the `xcodebuild` CLI). Its behavior is covered,
/// if at all, by a non-blocking `SKTestSession` integration test run in the Xcode IDE.
public struct StoreKitTransactionSource: EntitlementTransactionSource {
    public init() {}

    public func activeProductIDs() async -> Set<String> {
        var ids: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            ids.insert(transaction.productID)
        }
        return ids
    }
}

// MARK: - Production convenience

extension EntitlementProvider {
    /// Production default: the live StoreKit source. Kept in the app target so
    /// KigoCore stays StoreKit-free (ADR 0009).
    public init() {
        self.init(source: StoreKitTransactionSource())
    }
}
