import StoreKit
import Foundation

// MARK: - EntitlementSharedStore (now in EntitlementSharedStore.swift)
// `EntitlementSharedStore` protocol and `UserDefaultsEntitlementStore` have been
// factored into Sources/Kigo/EntitlementSharedStore.swift (slice #71) so that the
// widget extension and KigoWidgetTests can reach them without importing StoreKit.
// They are in the same Swift module (Kigo) so no import is needed here.

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

/// Derives subscription entitlement state from a `EntitlementTransactionSource`
/// and persists the result into an `EntitlementSharedStore`.
///
/// The caller does not need to understand StoreKit transaction types, verification,
/// or subscription groups: it asks `isEntitlementActive()` for the current state, or
/// calls `refreshEntitlement()` to re-derive and persist it. Both seams are injected
/// so the logic is testable headlessly with no `SKTestSession`/`storekitd` (ADR 0009).
/// `Sendable` — it holds only immutable, Sendable references.
public struct EntitlementProvider: Sendable {

    /// The product ID for the widget-access monthly subscription.
    /// Shared by all methods so the constant is never duplicated.
    /// Public so that `PaywallModel` (and other UI-layer callers) can surface the
    /// product ID without hard-coding the string outside this type.
    public static let widgetMonthlyProductID = "com.tomeitotameigo.kigo.widgets.monthly"

    private let source: EntitlementTransactionSource
    private let store: EntitlementSharedStore

    /// Production callers get the live StoreKit source and app-group UserDefaults store
    /// by default; tests inject fakes for both.
    public init(
        source: EntitlementTransactionSource = StoreKitTransactionSource(),
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
