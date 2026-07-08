import Foundation

// MARK: - EntitlementTransactionSource

/// The StoreKit seam: the set of product IDs the user currently holds a verified
/// entitlement for. This is the injection point that keeps `EntitlementProvider`'s
/// logic verifiable headlessly — tests fill it with an in-memory fake, so the
/// active/inactive derivation is exercised with no `SKTestSession`/`storekitd`
/// (which hangs under `xcodebuild` from the CLI — see ADR 0009 and CLAUDE.md).
///
/// The production conformance (`StoreKitTransactionSource`, over StoreKit 2's
/// `Transaction.currentEntitlements`) lives in the app target — this package is
/// StoreKit-free so its tests run host-side.
public protocol EntitlementTransactionSource: Sendable {
    /// Product IDs for which the user currently holds a verified entitlement.
    func activeProductIDs() async -> Set<String>
}

// MARK: - EntitlementProvider

/// Derives subscription entitlement state from a `EntitlementTransactionSource`.
///
/// The caller does not need to understand StoreKit transaction types, verification,
/// or subscription groups: it asks `isEntitlementActive()` for the current state,
/// re-derived from the injected source on each call. The seam is injected so the
/// logic is testable headlessly with no `SKTestSession`/`storekitd` (ADR 0009).
/// `Sendable` — it holds only immutable, Sendable references.
///
/// Since ADR 0019 inverted monetization off the widget, entitlement is no longer
/// shared to the widget extension: there is no persisted flag and no app-group
/// store — callers re-derive the current state directly from the source.
///
/// The zero-argument production form (`EntitlementProvider()`, live StoreKit
/// source) is an app-target extension next to `StoreKitTransactionSource`.
public struct EntitlementProvider: Sendable {

    /// The product ID for the widget-access monthly subscription.
    /// Shared by all methods so the constant is never duplicated.
    /// Public so that `PaywallModel` (and other UI-layer callers) can surface the
    /// product ID without hard-coding the string outside this type.
    public static let widgetMonthlyProductID = "com.tomeitotameigo.kigo.widgets.monthly"

    private let source: EntitlementTransactionSource

    /// Tests inject a fake source; production callers use the app-side
    /// zero-argument convenience (live StoreKit source).
    public init(source: EntitlementTransactionSource) {
        self.source = source
    }

    // MARK: - Entitlement check

    /// `true` iff the source reports a current, verified entitlement for the
    /// widget-access subscription. Derived from the source — never a hardcoded flag.
    public func isEntitlementActive() async -> Bool {
        await source.activeProductIDs().contains(Self.widgetMonthlyProductID)
    }
}
