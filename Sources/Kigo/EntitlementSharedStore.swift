import Foundation

// MARK: - EntitlementSharedStore
//
// Factored out of EntitlementProvider.swift (slice #71) so that the widget extension
// and KigoWidgetTests can reach the protocol without importing StoreKit.
//
// See ADR 0011 for the rationale behind this split.

/// The shared-store seam: persists the derived active flag so the Widget Gate (C7)
/// can read it from the app-group container without making a StoreKit call itself.
/// This is the injection point that keeps activation logic testable headlessly —
/// tests fill it with an in-memory actor fake; production backs it with app-group
/// `UserDefaults` (see `UserDefaultsEntitlementStore`).
public protocol EntitlementSharedStore: Sendable {
    /// The current value of the active flag.
    var isActive: Bool { get async }
    /// Persists the active flag. Called by `EntitlementProvider.refreshEntitlement()`.
    func setActive(_ value: Bool) async
}

// MARK: - UserDefaultsEntitlementStore (production)

/// Production backing: a thin wrapper over app-group `UserDefaults` for
/// `group.com.tomeitotameigo.kigo`. Deliberately thin — the only logic is
/// reading and writing one boolean key — so correctness is apparent on inspection.
/// The Widget extension reads the same key via the same app group.
/// `@unchecked Sendable`: `UserDefaults` is an Obj-C class that pre-dates Swift
/// concurrency; it is documented as thread-safe for `get`/`set` on shared instances.
public struct UserDefaultsEntitlementStore: @unchecked Sendable, EntitlementSharedStore {
    private static let key = "entitlement.isActive"
    private let defaults: UserDefaults

    public init() {
        // Falls back to `.standard` only if the app-group container is unavailable
        // (simulator without entitlement). The widget reads the same suite.
        self.defaults = UserDefaults(suiteName: "group.com.tomeitotameigo.kigo")
            ?? .standard
    }

    public var isActive: Bool {
        defaults.bool(forKey: Self.key)
    }

    public func setActive(_ value: Bool) {
        defaults.set(value, forKey: Self.key)
    }
}
