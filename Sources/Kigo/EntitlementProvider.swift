import StoreKit

// MARK: - EntitlementTransactionSource

/// The StoreKit seam: the set of product IDs the user currently holds a verified
/// entitlement for. This is the injection point that keeps `EntitlementProvider`'s
/// logic verifiable headlessly — tests fill it with an in-memory fake, so the
/// active/inactive derivation is exercised with no `SKTestSession`/`storekitd`
/// (which hangs under `xcodebuild` from the CLI — see ADR 0009 and CLAUDE.md).
public protocol EntitlementTransactionSource: Sendable {
    /// Product IDs for which the user currently holds a verified entitlement.
    func activeProductIDs() async -> Set<String>
}

// MARK: - StoreKitTransactionSource (production)

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

// MARK: - EntitlementProvider

/// Derives subscription entitlement state from a `EntitlementTransactionSource`.
///
/// The caller does not need to understand StoreKit transaction types, verification,
/// or subscription groups: it asks `isEntitlementActive()` and gets a Bool. The
/// StoreKit interaction is owned by the injected source (ADR 0009), so this type's
/// logic is pure and testable. `Sendable` — it holds only an immutable source.
public struct EntitlementProvider: Sendable {

    /// The product ID for the widget-access monthly subscription.
    private static let widgetMonthlyProductID = "com.tomeitotameigo.kigo.widgets.monthly"

    private let source: EntitlementTransactionSource

    /// Production callers get the live StoreKit source by default; tests inject a fake.
    public init(source: EntitlementTransactionSource = StoreKitTransactionSource()) {
        self.source = source
    }

    // MARK: - Entitlement check

    /// `true` iff the source reports a current, verified entitlement for the
    /// widget-access subscription. Derived from the source — never a hardcoded flag.
    public func isEntitlementActive() async -> Bool {
        await source.activeProductIDs().contains(Self.widgetMonthlyProductID)
    }
}
