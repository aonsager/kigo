import SwiftUI
import Foundation

// MARK: - PaywallView

/// The thin Paywall screen: presents the widget-access subscription product and
/// a Restore Purchases action. All presentation logic lives in `PaywallModel`
/// so it is testable headlessly with injected fakes (no `SKTestSession` / real
/// StoreKit call — see ADR 0009 / CLAUDE.md).
///
/// The purchase button surface exists here but no automated test drives a real
/// purchase. Real purchase flow (calling `AppStore.sync()` → StoreKit purchase
/// sheet → `PaywallModel.loadState()`) requires a live StoreKit session and is
/// exercised only via the Xcode IDE run path, never on the CLI gating path.
public struct PaywallView: View {
    @State private var model: PaywallModel

    public init(model: PaywallModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        // `paywall.sheet` is placed on a transparent overlay `Color.clear` that covers the
        // full sheet area. This makes the sheet presence machine-checkable by UI tests while
        // NOT inheriting the identifier onto the VStack and its Text children.
        //
        // On iOS 26 SwiftUI propagates an accessibilityIdentifier set on a Stack to ALL its
        // StaticText descendants (every child Text gets the container's identifier, overwriting
        // their own). By isolating `paywall.sheet` to a separate Color.clear element we avoid
        // that propagation, letting `paywall.price` and `paywall.duration` remain on the
        // individual Text views where the UI test expects them (ADR 0013 / slice #86).
        ZStack {
            // Invisible sentinel — carries `paywall.sheet` without overwriting children.
            Color.clear
                .accessibilityIdentifier("paywall.sheet")
                .accessibilityHidden(false)

            VStack(spacing: 24) {
                Text("Kigo Widgets")
                    .font(.largeTitle)
                    .bold()

                // Benefits copy — describes the single honest premium benefit (widget image reveal).
                // Carries `paywall.benefits` so the UI test can assert it is present and non-empty.
                Text("Reveal the seasonal illustration on your home screen widget.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("paywall.benefits")

                Text(model.productID)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                // Offer-display: price and duration surfaced via accessibility identifiers
                // so UI tests can assert on the rendered strings (slice #86 / ADR 0013).
                Text(model.price)
                    .font(.title2)
                    .bold()
                    .accessibilityIdentifier("paywall.price")

                Text(model.duration)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("paywall.duration")

                if model.isActive {
                    Label("Subscription active", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    // Purchase button surface. Carries `paywall.buy` for UI test assertions.
                    // Inert this milestone — no purchase flow is wired (that is C10).
                    // Wire to `AppStore.sync()` + StoreKit purchase sheet in C10 or later.
                    Button("Subscribe") {
                        // Purchase flow: out of scope for this slice (C10).
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("paywall.buy")
                }

                Button("Restore Purchases") {
                    Task { await model.restore() }
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("paywall.restore")

                // Legal links — placeholder URLs (ADR 0013 / J4).
                // Real legal copy and hosting are out of scope this milestone;
                // the URLs are gated as well-formed https constants in PaywallConfigTests.
                HStack(spacing: 16) {
                    Link("Terms of Use", destination: PaywallConfig.termsOfUseURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("paywall.terms")

                    Link("Privacy Policy", destination: PaywallConfig.privacyPolicyURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("paywall.privacy")
                }
            }
            .padding()
        }
        .task { await model.loadState() }
    }
}
