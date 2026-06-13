import Foundation

// MARK: - AppScreenState

/// The three screen states the app root can be in, derived from `ContentStore.state`.
///
/// Introduced in slice #60 to make the content-state mapping explicit, testable,
/// and crash-safe. `ContentView` switches on this value rather than branching
/// directly on `ContentStore.state` + optional-unwrap logic.
///
/// Cases:
/// - `today(ResolvedDay)`: Content loaded and today's entry resolved — show the Today screen.
/// - `loadingPlaceholder`: Content is loading (initial state or reload in progress) —
///   show a defined non-error placeholder; never a blank or broken screen.
/// - `unavailablePlaceholder`: Content could not be loaded (network/bundle error) —
///   show a defined non-error state; never crash.
///
/// `AppScreenState` is `Sendable` (all associated values are `Sendable`).
public enum AppScreenState: Sendable {
    /// Content loaded and today fully resolved — render `TodayView`.
    case today(ResolvedDay)
    /// Content is loading — render a non-error loading placeholder.
    case loadingPlaceholder
    /// Content is unavailable — render a non-error unavailable placeholder.
    case unavailablePlaceholder
}
