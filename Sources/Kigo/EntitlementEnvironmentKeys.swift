import SwiftUI

// MARK: - IsEntitledKey

/// SwiftUI environment key that propagates the current entitlement state through the view tree.
///
/// Slice #190: lifted from PaywallModel.isActive on RootView so TodayView can gate
/// premium content (kigo.description) without coupling to PaywallModel directly.
///
/// Default is `false` so any view without an explicit injection renders the unentitled state.
struct IsEntitledKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    /// `true` iff the user currently holds a verified entitlement for the widget-access subscription.
    var isEntitled: Bool {
        get { self[IsEntitledKey.self] }
        set { self[IsEntitledKey.self] = newValue }
    }
}

// MARK: - OpenPaywallAction

/// A `Sendable` wrapper around a `@MainActor` closure that presents the paywall sheet.
///
/// Slice #190: wrapping the closure in a struct satisfies Swift 6 strict concurrency
/// requirements for `EnvironmentKey.defaultValue` (a raw `() -> Void` is not `Sendable`).
/// Callers invoke it via `action()` on the main actor.
struct OpenPaywallAction: Sendable {
    private let body: @MainActor @Sendable () -> Void

    /// Creates a no-op action. Used as the environment key default.
    nonisolated init() {
        self.body = {}
    }

    /// Creates an action wrapping the given `@MainActor` closure.
    @MainActor
    init(_ body: @escaping @MainActor @Sendable () -> Void) {
        self.body = body
    }

    @MainActor
    func callAsFunction() {
        body()
    }
}

// MARK: - OpenPaywallKey

/// SwiftUI environment key that propagates the paywall-open action through the view tree.
///
/// Slice #190: injected from RootView so TodayView's upsell element can present the
/// paywall without coupling to the sheet-presentation state directly.
struct OpenPaywallKey: EnvironmentKey {
    static let defaultValue: OpenPaywallAction = OpenPaywallAction()
}

extension EnvironmentValues {
    /// An action that presents the paywall/settings sheet when called.
    var openPaywall: OpenPaywallAction {
        get { self[OpenPaywallKey.self] }
        set { self[OpenPaywallKey.self] = newValue }
    }
}
