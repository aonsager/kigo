import SwiftUI

/// App entry point for slice #56 (fake-date override).
///
/// Owns a single `ContentStore` over `BundledContentSource` (ADR 0006:
/// "a single instance is created at the app root and injected into the
/// SwiftUI environment"). The store begins loading immediately on init
/// and the injected `ContentView` observes its state reactively.
///
/// The `DateProvider` is resolved at startup via `launchDateProvider(environment:)`,
/// which reads the `KIGO_FAKE_DATE=YYYY-MM-DD` launch-environment variable.
/// When the variable is present and well-formed the store pins "today" to that
/// date for the entire session; otherwise it falls back to `SystemDateProvider`.
/// This makes the rendered Today screen deterministic under the environment
/// override (slice #56, acceptance criterion #1).
///
/// Slice #85: The `EntitlementProvider` is resolved via `launchEntitlementProvider(environment:)`,
/// which reads `KIGO_FAKE_ENTITLEMENT` to inject a fake source (active/inactive) or fall
/// through to the production StoreKit-backed provider. The `RootView` wrapper owns the
/// paywall entry and sheet-presentation state so it has access to the resolved provider.
///
/// Slice #86: The `OfferDisplay` is resolved via `launchOfferDisplay(environment:)`,
/// which reads `KIGO_FAKE_PRICE` to inject fixed price/duration strings or fall through
/// to the production placeholder (real `Product`-backed adapter is a J4 lane concern).
///
/// Slice #117: The `SubscriptionPurchaser` is resolved via `launchPurchaser(environment:)`,
/// which reads `KIGO_FAKE_PURCHASER` to inject a fake purchaser (succeed/cancel) or fall
/// through to the production `StoreKitSubscriptionPurchaser`. When `KIGO_FAKE_PURCHASER=succeed`
/// the resolver also returns a `MutableEntitlementTransactionSource` that the purchaser flips
/// on success; this override source is used to build the `EntitlementProvider` so the flip
/// is visible to `PaywallModel.buy()` → `provider.refreshEntitlement()` (ADR 0009).
@main
struct KigoApp: App {
    @State private var store = ContentStore(
        source: BundledContentSource(),
        dateProvider: launchDateProvider(environment: ProcessInfo.processInfo.environment)
    )

    private let entitlementProvider: EntitlementProvider
    private let purchaser: any SubscriptionPurchaser
    private let offerDisplay: OfferDisplay

    init() {
        let env = ProcessInfo.processInfo.environment
        offerDisplay = launchOfferDisplay(environment: env)

        if let fakePurchaser = launchPurchaser(environment: env) {
            // KIGO_FAKE_PURCHASER is set: use the resolved purchaser.
            // If it comes with an override source (succeed path), build the entitlement
            // provider over that mutable source so the flip is visible after purchase.
            purchaser = fakePurchaser.purchaser
            if let overrideSource = fakePurchaser.overrideSource {
                entitlementProvider = EntitlementProvider(source: overrideSource)
            } else {
                entitlementProvider = launchEntitlementProvider(environment: env)
            }
        } else {
            purchaser = StoreKitSubscriptionPurchaser()
            entitlementProvider = launchEntitlementProvider(environment: env)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(entitlementProvider: entitlementProvider, offerDisplay: offerDisplay, purchaser: purchaser)
                .environment(store)
        }
    }
}

// MARK: - RootView

/// Thin wrapper around `ContentView` that owns the paywall entry and sheet state.
///
/// Placing entry+sheet ownership here (rather than inside `TodayView` or `ContentView`)
/// keeps `ContentView` free of paywall concerns and gives `RootView` unambiguous access
/// to the resolved `EntitlementProvider` and `OfferDisplay` passed down from `KigoApp`.
///
/// The Upgrade button (`paywall.entry`) is always present, overlaid as a small, unobtrusive
/// control at the bottom-trailing corner of the screen via a `ZStack` / `overlay`.
struct RootView: View {
    let entitlementProvider: EntitlementProvider
    let offerDisplay: OfferDisplay
    let purchaser: any SubscriptionPurchaser

    @State private var isPaywallPresented = false

    var body: some View {
        ContentView()
            .overlay(alignment: .bottomTrailing) {
                Button("Upgrade") {
                    isPaywallPresented = true
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .accessibilityIdentifier("paywall.entry")
            }
            .sheet(isPresented: $isPaywallPresented) {
                PaywallView(model: PaywallModel(
                    provider: entitlementProvider,
                    offerDisplay: offerDisplay,
                    purchaser: purchaser
                ))
            }
    }
}
