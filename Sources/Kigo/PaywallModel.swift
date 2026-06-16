import Foundation
import Observation
import StoreKit

// MARK: - PaywallModel

/// Observable view model for the Paywall screen.
///
/// Wraps an injected `EntitlementProvider` and exposes the reflected `isActive`
/// state to the SwiftUI view. The injection point is what keeps the Paywall's
/// logic headlessly testable: tests inject a fake `EntitlementTransactionSource`
/// and a fake `EntitlementSharedStore`; there is no `SKTestSession`, no
/// `buyProduct`, and no real StoreKit call on the gating test path (ADR 0009 /
/// CLAUDE.md). The production app passes a `EntitlementProvider` built with the
/// live StoreKit source and the app-group shared store.
///
/// - `productID`: the widget-access product ID, exposed so the view can display
///   the product surface without hard-coding the constant in the UI layer.
/// - `price`: localised price string from the injected `OfferDisplay`, e.g. "¥300".
/// - `duration`: localised duration string from the injected `OfferDisplay`, e.g. "1 month".
/// - `isActive`: the reflected entitlement flag; updated by `loadState()` and
///   `restore()`.
/// - `loadState()`: re-derives the current entitlement from the source and
///   refreshes `isActive`. Call on view appear.
/// - `restore()`: invokes the entitlement engine's restore path, then re-reads
///   `isActive`. Wired to the Restore button in `PaywallView`.
@MainActor
@Observable
public final class PaywallModel {

    // MARK: - Product surface

    /// The widget-access monthly subscription product ID.
    /// Presented by the view so users know which product they are purchasing.
    public let productID: String = EntitlementProvider.widgetMonthlyProductID

    // MARK: - Offer display

    /// The localised price string for the subscription offer, e.g. "¥300".
    /// Sourced from the injected `OfferDisplay`; tests inject a `FixedOfferDisplay`
    /// with a known string — no real StoreKit `Product` is ever loaded on the test path.
    public let price: String

    /// The localised duration string for the subscription offer, e.g. "1 month".
    /// Non-empty in all conformers (fixed fakes use "1 month"; production uses the
    /// subscription period from the resolved `Product`).
    public let duration: String

    // MARK: - Reflected state

    /// `true` iff the user currently holds a verified entitlement for the
    /// widget-access subscription. Updated by `loadState()` and `restore()`.
    public private(set) var isActive: Bool = false

    // MARK: - Injected provider

    private let provider: EntitlementProvider

    // MARK: - Injected purchaser

    /// The subscription purchaser seam. Tests inject a `FakeSubscriptionPurchaser`;
    /// production uses `StoreKitSubscriptionPurchaser()`. Defaulted so existing
    /// call sites that omit the parameter compile without change (ADR 0009).
    private let purchaser: SubscriptionPurchaser

    // MARK: - Init

    /// - Parameters:
    ///   - provider: The entitlement provider. Tests inject a provider built with
    ///     in-memory fakes; production passes the live provider.
    ///   - offerDisplay: The offer-display value carrying the price and duration
    ///     strings. Defaults to a placeholder so existing call sites that omit it
    ///     compile without change; production and UI-test call sites should pass
    ///     the resolved `launchOfferDisplay(environment:)` value.
    ///   - purchaser: The subscription purchaser. Defaults to the production
    ///     `StoreKitSubscriptionPurchaser`; tests inject a fake.
    public init(
        provider: EntitlementProvider,
        offerDisplay: OfferDisplay = OfferDisplay(price: "—", duration: "Monthly"),
        purchaser: SubscriptionPurchaser = StoreKitSubscriptionPurchaser()
    ) {
        self.provider = provider
        self.price = offerDisplay.price
        self.duration = offerDisplay.duration
        self.purchaser = purchaser
    }

    // MARK: - Actions

    /// Re-derives the current entitlement from the source and updates `isActive`.
    /// Call on view appear to initialize reflected state.
    public func loadState() async {
        isActive = await provider.isEntitlementActive()
    }

    /// Invokes the entitlement engine's restore path (which re-derives the active
    /// flag from the transaction source and persists it into the shared store),
    /// then re-reads the reflected state so the view updates immediately.
    ///
    /// In production, `AppStore.sync()` should be called *before* this to refresh
    /// the transaction journal. That live-sync step is deliberately outside the
    /// model: it is un-testable headlessly and is left to the production call site
    /// or a manual integration lane. The restore *logic* verified here is the
    /// derive-and-persist path through the injected seam.
    public func restore() async {
        await provider.restoreEntitlement()
        isActive = await provider.isEntitlementActive()
    }

    /// Initiates a subscription purchase for the widget-access product via the
    /// injected `SubscriptionPurchaser` seam.
    ///
    /// On success, calls `provider.refreshEntitlement()` (which re-derives and
    /// persists the active flag) then re-reads `isActive` so the view updates.
    ///
    /// On cancellation (`SubscriptionPurchaserCancellation`) or any other error,
    /// the error is swallowed and `isActive` is left unchanged — no crash on any
    /// path. The model does NOT surface a visible error state this milestone; that
    /// is out of scope (see slice #116 PRD).
    ///
    /// Driving a real purchase via `Product.purchase()` headlessly hangs under
    /// `xcodebuild` from the CLI (ADR 0009 / CLAUDE.md). Tests inject a
    /// `FakeSubscriptionPurchaser` configured to succeed, throw cancellation, or
    /// throw an arbitrary error.
    public func buy() async {
        do {
            try await purchaser.purchase(productID)
            await provider.refreshEntitlement()
            isActive = await provider.isEntitlementActive()
        } catch {
            // Swallow both cancellation and unexpected errors — no crash on any path.
            // isActive is intentionally left unchanged.
        }
    }
}
