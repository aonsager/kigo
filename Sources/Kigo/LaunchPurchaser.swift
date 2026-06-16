import Foundation

// MARK: - launchPurchaser

/// Reads the `KIGO_FAKE_PURCHASER` launch-environment variable and returns a tuple
/// of `(purchaser, overrideSource)` for fake injection, or `nil` when the variable
/// is absent (indicating the production `StoreKitSubscriptionPurchaser` should be used).
///
/// Recognised values:
/// - `"succeed"` → a purchaser that succeeds silently and flips the bundled mutable
///   entitlement source to report the widget product as owned. The `overrideSource`
///   in the tuple is a `MutableEntitlementTransactionSource` pre-seeded as empty
///   and must be passed to `launchEntitlementProvider` (overriding the env-var path)
///   so the purchaser's flip is visible to the provider.
/// - `"cancel"` → a purchaser that throws `SubscriptionPurchaserCancellation`.
///   The `overrideSource` is `nil` — the entitlement source from `KIGO_FAKE_ENTITLEMENT`
///   is left unchanged.
/// - anything else (including absent) → `nil`.
///
/// - Parameter environment: The launch-environment dictionary, typically
///   `ProcessInfo.processInfo.environment` at the app root.
/// - Returns: A tuple of `(SubscriptionPurchaser, MutableEntitlementTransactionSource?)`
///   or `nil` when `KIGO_FAKE_PURCHASER` is absent or unrecognised.
public func launchPurchaser(
    environment: [String: String]
) -> (purchaser: any SubscriptionPurchaser, overrideSource: MutableEntitlementTransactionSource?)? {
    switch environment["KIGO_FAKE_PURCHASER"] {
    case "succeed":
        let source = MutableEntitlementTransactionSource()
        let purchaser = FlippingFakePurchaser(source: source)
        return (purchaser: purchaser, overrideSource: source)
    case "cancel":
        let purchaser = CancellingFakePurchaser()
        return (purchaser: purchaser, overrideSource: nil)
    default:
        return nil
    }
}

// MARK: - MutableEntitlementTransactionSource

/// A mutable, actor-isolated `EntitlementTransactionSource` that starts empty and
/// can be flipped to report the widget-access product as owned.
///
/// Used by the `KIGO_FAKE_PURCHASER=succeed` injection seam: a `FlippingFakePurchaser`
/// holds a reference to this source and calls `flip()` when `purchase(_:)` is called,
/// causing the subsequent `provider.refreshEntitlement()` to see the widget product
/// as active — without any real StoreKit call or `storekitd` involvement (ADR 0009).
public actor MutableEntitlementTransactionSource: EntitlementTransactionSource {
    private var productIDs: Set<String> = []

    public init() {}

    /// Reports the currently active product IDs.
    public func activeProductIDs() async -> Set<String> {
        productIDs
    }

    /// Seeds the source with the widget-access product ID so subsequent
    /// `activeProductIDs()` calls report it as owned. Called by `FlippingFakePurchaser`
    /// on a simulated successful purchase.
    public func flip() {
        productIDs = [EntitlementProvider.widgetMonthlyProductID]
    }
}

// MARK: - FlippingFakePurchaser

/// A `SubscriptionPurchaser` that succeeds silently and flips the bundled
/// `MutableEntitlementTransactionSource` so that the `EntitlementProvider`'s
/// subsequent `refreshEntitlement()` call sees the widget product as active.
///
/// Only used on the `KIGO_FAKE_PURCHASER=succeed` injection path (UI tests).
/// Never touches the real StoreKit purchase path (ADR 0009).
struct FlippingFakePurchaser: SubscriptionPurchaser {
    let source: MutableEntitlementTransactionSource

    func purchase(_ productID: String) async throws {
        await source.flip()
        // Returns normally — no error, no sheet, no storekitd.
    }
}

// MARK: - CancellingFakePurchaser

/// A `SubscriptionPurchaser` that always throws `SubscriptionPurchaserCancellation`.
/// Used on the `KIGO_FAKE_PURCHASER=cancel` injection path (UI tests verifying the
/// no-crash, no-dismiss path).
struct CancellingFakePurchaser: SubscriptionPurchaser {
    func purchase(_ productID: String) async throws {
        throw SubscriptionPurchaserCancellation()
    }
}
