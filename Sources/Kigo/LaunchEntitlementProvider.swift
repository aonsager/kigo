import Foundation

// MARK: - fakeEntitlementSource

/// Reads the `KIGO_FAKE_ENTITLEMENT` launch-environment variable and returns an
/// in-memory fake `EntitlementTransactionSource`, or `nil` when the variable is
/// absent or unrecognised (indicating the production StoreKit-backed path should be used).
///
/// Recognised values:
/// - `"active"`   → a source reporting `EntitlementProvider.widgetMonthlyProductID`
///                  (the user appears entitled to the widget product).
/// - `"inactive"` → a source reporting an empty set (no entitlements).
/// - anything else (including absent) → `nil` (caller uses default / production init).
///
/// This is the injection seam that makes the entitlement resolver headlessly testable:
/// the unit test passes a `[String: String]` dictionary, asserts the source is non-nil
/// for "active"/"inactive" (drives `isEntitlementActive()` true/false through the
/// built provider), and asserts `nil` when absent — verifying the production path is
/// taken WITHOUT ever calling `isEntitlementActive()` on a real `EntitlementProvider`
/// (which would reach `Transaction.currentEntitlements` / `storekitd` and hang under
/// `xcodebuild` from the CLI; see ADR 0009 and CLAUDE.md).
///
/// - Parameter environment: The launch-environment dictionary, typically
///   `ProcessInfo.processInfo.environment` at the app root.
/// - Returns: A fake `EntitlementTransactionSource` for "active" or "inactive",
///   or `nil` when the key is absent or the value is unrecognised.
public func fakeEntitlementSource(environment: [String: String]) -> (any EntitlementTransactionSource)? {
    switch environment["KIGO_FAKE_ENTITLEMENT"] {
    case "active":
        return FixedEntitlementTransactionSource(
            productIDs: [EntitlementProvider.widgetMonthlyProductID]
        )
    case "inactive":
        return FixedEntitlementTransactionSource(productIDs: [])
    default:
        return nil
    }
}

// MARK: - launchEntitlementProvider

/// Resolves the `EntitlementProvider` to use at app launch, reading
/// `KIGO_FAKE_ENTITLEMENT` from the launch environment.
///
/// - `=active`   → `EntitlementProvider` over an in-memory fake source reporting
///                 the widget product as owned.
/// - `=inactive` → `EntitlementProvider` over an in-memory fake source reporting
///                 no products (empty set).
/// - absent      → default `EntitlementProvider()` (production, StoreKit-backed).
///
/// - Parameter environment: The launch-environment dictionary, typically
///   `ProcessInfo.processInfo.environment` at the app root.
/// - Returns: The resolved `EntitlementProvider`.
public func launchEntitlementProvider(environment: [String: String]) -> EntitlementProvider {
    if let source = fakeEntitlementSource(environment: environment) {
        return EntitlementProvider(source: source)
    }
    return EntitlementProvider()
}

// MARK: - FixedEntitlementTransactionSource

/// In-memory fake `EntitlementTransactionSource` that reports a fixed set of product IDs.
/// Used by the launch resolver for the `KIGO_FAKE_ENTITLEMENT` injection seam.
public struct FixedEntitlementTransactionSource: EntitlementTransactionSource {
    private let productIDs: Set<String>

    public init(productIDs: Set<String>) {
        self.productIDs = productIDs
    }

    public func activeProductIDs() async -> Set<String> {
        productIDs
    }
}
