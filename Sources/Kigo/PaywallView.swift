import SwiftUI

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
        // The ZStack root carries `paywall.sheet` so the sheet's presence is
        // machine-checkable by the UI test before inner content surfaces exist.
        // ZStack with .frame(maxWidth:maxHeight:) renders as an accessible container
        // (`otherElements`) that XCUI can locate by identifier even on iOS 26.
        ZStack {
            VStack(spacing: 24) {
                Text("Kigo Widgets")
                    .font(.largeTitle)
                    .bold()

                Text("Unlock widget access with the monthly subscription.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Text(model.productID)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                if model.isActive {
                    Label("Subscription active", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    // Purchase button surface. In production this would invoke the
                    // StoreKit purchase sheet. No test drives a real purchase (see
                    // CLAUDE.md / ADR 0009 — it hangs under xcodebuild from the CLI).
                    Button("Subscribe") {
                        // Purchase flow: out of scope for this slice.
                        // Wire to `AppStore.sync()` + StoreKit purchase sheet in C7 or later.
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button("Restore Purchases") {
                    Task { await model.restore() }
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("paywall.sheet")
        .task { await model.loadState() }
    }
}
