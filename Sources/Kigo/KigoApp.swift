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
///
/// Slice #136: An `InMemoryLanguageStore` is created at app startup and injected into
/// `RootView` → `PaywallView` so the Paywall's chrome strings react to the user's
/// language preference. Persistence (UserDefaults) and the `KIGO_FAKE_LANGUAGE` resolver
/// are deferred to slice #137.
///
/// Slice #137: `launchLanguageStore(environment:)` replaces the hardcoded `InMemoryLanguageStore`.
/// It returns a locked store for `KIGO_FAKE_LANGUAGE=en/ja`, or `UserDefaultsLanguageStore`
/// (persisted) when the env var is absent (ADR 0013 pattern).
///
/// Slice #144: `launchColorScheme(environment:)` resolves an optional `ColorScheme` from
/// `KIGO_FAKE_APPEARANCE=dark/light`, applied via `.preferredColorScheme(_:)` on the root
/// `WindowGroup` view. Absent or unrecognised values leave the system in control (nil).
@main
struct KigoApp: App {
    @State private var store = ContentStore(
        source: BundledContentSource(),
        dateProvider: launchDateProvider(environment: ProcessInfo.processInfo.environment)
    )

    private let entitlementProvider: EntitlementProvider
    private let purchaser: any SubscriptionPurchaser
    private let offerDisplay: OfferDisplay
    private let languageStore: any LanguageStore
    private let colorScheme: ColorScheme?

    init() {
        let env = ProcessInfo.processInfo.environment
        offerDisplay = launchOfferDisplay(environment: env)
        languageStore = launchLanguageStore(environment: env)
        colorScheme = launchColorScheme(environment: env)

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
            RootView(
                entitlementProvider: entitlementProvider,
                offerDisplay: offerDisplay,
                purchaser: purchaser,
                languageStore: languageStore
            )
            .environment(store)
            .preferredColorScheme(colorScheme)
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
///
/// Slice #136: `languageStore` carries the user's language preference; `ChromeStrings` is
/// derived at sheet-construction time and passed into `PaywallView` so the restore label
/// reflects the active locale.
///
/// Slice #137: `languageStore` is now typed as `any LanguageStore` to accommodate both
/// `UserDefaultsLanguageStore` (production) and `LockedInMemoryLanguageStore` (fake env path).
struct RootView: View {
    let entitlementProvider: EntitlementProvider
    let offerDisplay: OfferDisplay
    let purchaser: any SubscriptionPurchaser
    let languageStore: any LanguageStore

    @State private var isPaywallPresented = false

    var body: some View {
        ContentView()
            .overlay(alignment: .bottomTrailing) {
                Button {
                    isPaywallPresented = true
                } label: {
                    Image(systemName: "gearshape.fill")
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .accessibilityIdentifier("paywall.entry")
            }
            .sheet(isPresented: $isPaywallPresented) {
                SettingsView(
                    model: PaywallModel(
                        provider: entitlementProvider,
                        offerDisplay: offerDisplay,
                        purchaser: purchaser
                    ),
                    languageStore: languageStore
                )
            }
    }
}
