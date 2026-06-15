import Foundation

// MARK: - OfferDisplay

/// A value type that carries the display strings for a subscription offer.
///
/// Kept as a plain struct (not a protocol with async requirements) because
/// the Paywall only needs synchronous display strings — price and duration.
/// The production adapter reads these from a resolved StoreKit `Product`
/// *before* being injected; it is never called inside a test (ADR 0009).
public struct OfferDisplay {
    /// The localised price string, e.g. "¥300" or "$2.99".
    public let price: String

    /// The localised subscription-period string, e.g. "1 month" or "Monthly".
    public let duration: String

    public init(price: String, duration: String) {
        self.price = price
        self.duration = duration
    }
}

// MARK: - launchOfferDisplay

/// Reads the `KIGO_FAKE_PRICE` launch-environment variable and, when present,
/// returns a `FixedOfferDisplay` with that price string and a fixed duration
/// of `"1 month"`. When the variable is absent the function returns a
/// `FixedOfferDisplay` whose values come from the production StoreKit product
/// record — in practice the production app will later swap this for a real
/// `Product`-backed value, but for the current gating path (headless tests,
/// fake-env UI tests) the fixed strings are sufficient.
///
/// This is a pure function over `[String: String]` so unit tests can exercise
/// both branches without launching the app (mirrors `launchEntitlementProvider`
/// and `launchDateProvider`).
///
/// - Parameter environment: The launch-environment dictionary, typically
///   `ProcessInfo.processInfo.environment` at the app root.
/// - Returns: A `FixedOfferDisplay` seeded from the env var, or the production
///   offer display when `KIGO_FAKE_PRICE` is absent.
public func launchOfferDisplay(environment: [String: String]) -> OfferDisplay {
    if let fakePrice = environment["KIGO_FAKE_PRICE"] {
        return OfferDisplay(price: fakePrice, duration: "1 month")
    }
    // Production path: the thin production adapter over a real StoreKit Product
    // would be resolved here. For the current gating path we return a sensible
    // default — the real Product is never loaded on the headless test path (ADR 0009).
    return productionOfferDisplay()
}

// MARK: - Private

/// Returns the production offer-display strings.
///
/// In the shipping product this would resolve a `StoreKit.Product` for the
/// widget-monthly SKU and read `product.displayPrice` and
/// `product.subscription?.subscriptionPeriod` from it. That path requires a
/// live `storekitd` and is not exercised headlessly (ADR 0009).
///
/// For the current slice the function returns a placeholder so the Paywall has
/// non-empty strings when launched without the fake env var (e.g. Xcode
/// Preview / manual run). The real adapter is a J4-lane concern.
private func productionOfferDisplay() -> OfferDisplay {
    OfferDisplay(price: "—", duration: "Monthly")
}
