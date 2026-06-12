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

    /// The task spawned on init (and on reload). Stored so `waitForLoad()` can
    /// await it deterministically in tests without introducing sleep/polling.
    private var loadTask: Task<Void, Never>?

    // MARK: Init

    /// Creates a `ContentStore` backed by the given `ContentSource` and immediately
    /// begins loading. The caller does not need to trigger a separate `load()` call.
    ///
    /// - Parameter source: A `ContentSource` implementation (production or test fake).
    public init(source: any ContentSource) {
        self.source = source
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

    // MARK: - Testability

    /// Awaits the in-flight load task. Intended for use in tests to deterministically
    /// wait until the store has transitioned out of `.loading` without polling.
    ///
    /// In production code, observe `state` reactively via `@Observable` / `.onChange`.
    public func waitForLoad() async {
        await loadTask?.value
    }
}
