import Foundation
import Observation

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

    // MARK: - Reflected state

    /// `true` iff the user currently holds a verified entitlement for the
    /// widget-access subscription. Updated by `loadState()` and `restore()`.
    public private(set) var isActive: Bool = false

    // MARK: - Injected provider

    private let provider: EntitlementProvider

    // MARK: - Init

    /// - Parameter provider: The entitlement provider. Tests inject a provider
    ///   built with in-memory fakes; production passes the live provider.
    public init(provider: EntitlementProvider) {
        self.provider = provider
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
}
