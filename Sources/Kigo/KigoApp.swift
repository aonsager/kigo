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
@main
struct KigoApp: App {
    @State private var store = ContentStore(
        source: BundledContentSource(),
        dateProvider: launchDateProvider(environment: ProcessInfo.processInfo.environment)
    )

    private let entitlementProvider = launchEntitlementProvider(
        environment: ProcessInfo.processInfo.environment
    )

    var body: some Scene {
        WindowGroup {
            RootView(entitlementProvider: entitlementProvider)
                .environment(store)
        }
    }
}

// MARK: - RootView

/// Thin wrapper around `ContentView` that owns the paywall entry and sheet state.
///
/// Placing entry+sheet ownership here (rather than inside `TodayView` or `ContentView`)
/// keeps `ContentView` free of paywall concerns and gives `RootView` unambiguous access
/// to the resolved `EntitlementProvider` passed down from `KigoApp`.
///
/// The Upgrade button (`paywall.entry`) is always present, overlaid as a small, unobtrusive
/// control at the bottom-trailing corner of the screen via a `ZStack` / `overlay`.
struct RootView: View {
    let entitlementProvider: EntitlementProvider

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
                PaywallView(model: PaywallModel(provider: entitlementProvider))
            }
    }
}
