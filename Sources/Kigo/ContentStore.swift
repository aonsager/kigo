import Foundation
import Observation

// MARK: - ContentState

/// The observable state that `ContentStore` exposes to its consumers.
///
/// Defined per ADR 0006 (docs/adr/0006-contentstore-state-and-caching.md).
/// - `loading` is the initial state; the store begins loading on initialisation
///   and there is no separate "not started" case.
/// - `loaded(Manifest)` carries the decoded manifest so callers need no optional unwrap.
/// - `unavailable(Error)` surfaces the underlying failure so the UI can display it
///   without re-throwing (the store's public API is non-throwing).
///
/// The enum is `Sendable`; `Manifest` is already `Sendable` and `Error` is a protocol.
/// Concrete errors stored in the `unavailable` case must also be `Sendable`
/// (both `BundledContentSourceError` and system `Foundation` errors satisfy this).
public enum ContentState: Sendable {
    case loading
    case loaded(Manifest)
    case unavailable(Error)
}

// MARK: - ContentStore

/// Orchestrates a `ContentSource` and exposes an observable, non-erroring state
/// to SwiftUI consumers.
///
/// Ownership model (ADR 0006):
/// - A single instance is created at the app root and injected into the SwiftUI
///   environment via `.environment(\.contentStore, store)`.
/// - The in-memory cache is the `.loaded(Manifest)` associated value; there is no
///   disk persistence in C3.
/// - `ContentSource` is called once on init (and again on explicit `reload()`).
///   Subsequent reads are served from the cached state without re-decoding.
///
/// Concurrency:
/// - `@MainActor` pins observation mutations to the main actor, which is required
///   for `@Observable` classes used in SwiftUI; it also eliminates data-race warnings
///   under Swift 6 strict concurrency.
/// - The async `load()` call to `ContentSource` is awaited inside a `Task` that is
///   isolated to `@MainActor`; `await source.load()` suspends and resumes on the
///   main actor, which is correct because `ContentSource.load()` is `async throws`
///   and carries no actor requirement of its own.
@MainActor
@Observable
public final class ContentStore {

    // MARK: Public state

    /// The current content-loading state. Observe this from SwiftUI views.
    public private(set) var state: ContentState = .loading

    // MARK: Private

    private let source: any ContentSource

    /// Provides the current date for day-key derivation. Injected for testability.
    private let dateProvider: any DateProvider

    // Day-key derivation is provided by `DayKey.make(from:)` (DayKey.swift).
    // The UTC calendar is defined there; ContentStore references it through that
    // single shared implementation rather than maintaining its own copy.

    /// The task spawned on init (and on reload). Stored so `waitForLoad()` can
    /// await it deterministically in tests without introducing sleep/polling.
    private var loadTask: Task<Void, Never>?

    // MARK: Init

    /// Creates a `ContentStore` backed by the given `ContentSource` and immediately
    /// begins loading. The caller does not need to trigger a separate `load()` call.
    ///
    /// - Parameters:
    ///   - source: A `ContentSource` implementation (production or test fake).
    ///   - dateProvider: Provider for "today". Defaults to `SystemDateProvider`
    ///     (current system clock). Inject a `FixedDateProvider` in tests.
    public init(source: any ContentSource, dateProvider: any DateProvider = SystemDateProvider()) {
        self.source = source
        self.dateProvider = dateProvider
        startLoading()
    }

    // MARK: - Internal loading

    private func startLoading() {
        state = .loading
        loadTask = Task {
            do {
                let manifest = try await source.load()
                state = .loaded(manifest)
            } catch {
                // Encapsulate the source error: no error type escapes to the caller.
                // The unavailable case carries the error so the UI can surface it.
                state = .unavailable(error)
            }
        }
    }

    // MARK: - Today's entry

    /// Returns today's `DailyMapEntry` from the in-memory cache, or `nil` if the
    /// manifest has not yet loaded or does not contain an entry for today's day-key.
    ///
    /// The day-key is derived from `dateProvider.today` using UTC: `"MM-DD"`.
    /// This implements the bare `dailyMap["MM-DD"]` lookup specified in ADR 0006 (C3
    /// scope). No Kō/Sekki resolution is performed here — that is C4 scope.
    ///
    /// This method reads only from the already-cached `.loaded(Manifest)` associated
    /// value and never calls `source.load()`, satisfying the offline-survival guarantee:
    /// once the cache is warm, serving today's entry requires no source access at all.
    public func todayEntry() -> DailyMapEntry? {
        guard case .loaded(let manifest) = state else { return nil }
        guard let key = DayKey.make(from: dateProvider.today) else { return nil }
        return manifest.dailyMap[key]
    }

    /// Resolves the full `ResolvedDay` (Kigo entry + Kō + Sekki) for the date produced
    /// by the injected `DateProvider`.
    ///
    /// This is the correct seam for the Today screen (AC4 of slice #55): it ensures
    /// "today" flows from the provider that was injected at the app root, never from a
    /// raw `Date()` call inside a view. Slice #56 can substitute a `FixedDateProvider`
    /// at the app root and this path automatically uses the overridden date.
    ///
    /// Returns `nil` if the manifest has not yet loaded, or if the derived day-key has
    /// no matching entry (or no containing Kō) in the manifest.
    public func todayResolved() -> ResolvedDay? {
        guard case .loaded(let manifest) = state else { return nil }
        return TodayResolver.resolve(date: dateProvider.today, manifest: manifest)
    }

    // MARK: - Screen-state mapping

    /// Maps the current `ContentState` to the `AppScreenState` that the app root should render.
    ///
    /// This is the single authoritative mapping for slice #60 (AC4). `ContentView` switches on
    /// this value; there is no conditional logic scattered across views.
    ///
    /// - `.loading` → `.loadingPlaceholder` (defined, non-crashing)
    /// - `.loaded` where `todayResolved()` succeeds → `.today(ResolvedDay)`
    /// - `.loaded` where `todayResolved()` returns nil (no entry for today) → `.unavailablePlaceholder`
    ///   (a content gap is terminal — waiting cannot resolve it — so it surfaces the
    ///   defined non-error *terminal* state, never an indefinite loading spinner)
    /// - `.unavailable` → `.unavailablePlaceholder` (defined, non-crashing)
    public var screenState: AppScreenState {
        switch state {
        case .loading:
            return .loadingPlaceholder
        case .loaded:
            if let resolved = todayResolved() {
                return .today(resolved)
            } else {
                return .unavailablePlaceholder
            }
        case .unavailable:
            return .unavailablePlaceholder
        }
    }

    // MARK: - Testability

    /// Awaits the in-flight load task. Intended for use in tests to deterministically
    /// wait until the store has transitioned out of `.loading` without polling.
    ///
    /// In production code, observe `state` reactively via `@Observable` / `.onChange`.
    public func waitForLoad() async {
        await loadTask?.value
    }
}
