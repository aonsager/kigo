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

/// Derives subscription entitlement state from a `EntitlementTransactionSource`
/// and persists the result into an `EntitlementSharedStore`.
///
/// The caller does not need to understand StoreKit transaction types, verification,
/// or subscription groups: it asks `isEntitlementActive()` for the current state, or
/// calls `refreshEntitlement()` to re-derive and persist it. Both seams are injected
/// so the logic is testable headlessly with no `SKTestSession`/`storekitd` (ADR 0009).
/// `Sendable` — it holds only immutable, Sendable references.
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
    private let store: EntitlementSharedStore

    /// Tests inject fakes for both seams; production callers use the app-side
    /// zero-argument convenience (live StoreKit source, app-group store).
    public init(
        source: EntitlementTransactionSource,
        store: EntitlementSharedStore = UserDefaultsEntitlementStore()
    ) {
        self.source = source
        self.store = store
    }

    // MARK: - Entitlement check

    /// `true` iff the source reports a current, verified entitlement for the
    /// widget-access subscription. Derived from the source — never a hardcoded flag.
    public func isEntitlementActive() async -> Bool {
        await source.activeProductIDs().contains(Self.widgetMonthlyProductID)
    }

    // MARK: - Activation / refresh

    /// Re-derives the active flag from the source and persists it into the shared store.
    /// Call this on app launch and after purchase/restore to keep the Widget Gate (C7)
    /// in sync. The shared store is app-group `UserDefaults` in production.
    public func refreshEntitlement() async {
        let active = await isEntitlementActive()
        await store.setActive(active)
    }

    // MARK: - Restore

    /// Re-derives the active flag from the source and re-writes the shared store.
    /// Models the "Restore Purchases" path: call this after the user taps Restore
    /// (in production, run `AppStore.sync()` first to refresh the transaction
    /// journal, then call this). The implementation is intentionally identical to
    /// `refreshEntitlement()` — both re-derive from the injected source and persist
    /// into the injected store — so the restore path is exercised purely through the
    /// injected fakes in tests, with no `SKTestSession`, no `buyProduct`, and no
    /// real StoreKit call (which hangs under `xcodebuild` from the CLI; ADR 0009).
    public func restoreEntitlement() async {
        let active = await isEntitlementActive()
        await store.setActive(active)
    }
}
