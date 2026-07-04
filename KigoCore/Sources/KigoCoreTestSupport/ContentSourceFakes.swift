import Foundation
import KigoCore

// Shared test fakes for `ContentSource`, used by BOTH lanes: the package's own
// host-side tests (KigoCoreTests) and the app's sim-lane tests (KigoTests).
// Living in a library product (not a test target) is what makes them importable
// from both — test targets cannot import each other.

// MARK: - FakeContentSource

/// A test-only in-process fake `ContentSource` that returns a known `Manifest`
/// without any network, file I/O, or bundle access.
///
/// Using an in-memory fake (not a mock library) keeps the test fully self-contained
/// and verifies the store's behavior through its public API only.
public struct FakeContentSource: ContentSource {
    public let manifest: Manifest

    public init(manifest: Manifest) {
        self.manifest = manifest
    }

    public func load() async throws -> Manifest {
        return manifest
    }
}

// MARK: - FailingContentSource

/// A test-only in-process fake `ContentSource` that always throws on `load()`.
/// Used to verify the cold-start guarantee: an empty cache + failing source
/// must never surface a thrown error to the caller; the store resolves to
/// `.unavailable` instead.
public struct FailingContentSource: ContentSource {
    public struct LoadFailure: Error {
        public init() {}
    }

    public init() {}

    public func load() async throws -> Manifest { throw LoadFailure() }
}

// MARK: - HoldingFakeContentSource

/// A fake `ContentSource` that suspends until explicitly resumed.
/// Used to observe the `.loading` initial state before load completes.
///
/// Implemented with an `AsyncStream` continuation so no external synchronisation
/// primitive is needed — the store's Task suspends at `await source.load()` and
/// resumes only when `resume()` is called from the test.
public final class HoldingFakeContentSource: ContentSource, @unchecked Sendable {
    private let manifest: Manifest
    private var continuation: AsyncStream<Void>.Continuation?
    private let stream: AsyncStream<Void>

    public init(manifest: Manifest) {
        self.manifest = manifest
        var cap: AsyncStream<Void>.Continuation?
        self.stream = AsyncStream { cap = $0 }
        self.continuation = cap
    }

    /// Signals the suspended `load()` call to complete.
    public func resume() {
        continuation?.yield(())
        continuation?.finish()
    }

    public func load() async throws -> Manifest {
        // Suspend until resume() is called.
        for await _ in stream { break }
        return manifest
    }
}

// MARK: - CountingFakeContentSource

/// A test-only `ContentSource` that counts `load()` invocations.
/// The first call returns the provided `Manifest`; subsequent calls throw.
/// This lets tests assert that `todayEntry()` serves from cache without
/// re-invoking the source.
public actor CountingFakeContentSource: ContentSource {
    public let manifest: Manifest
    public private(set) var loadCallCount: Int = 0

    public init(manifest: Manifest) {
        self.manifest = manifest
    }

    public func load() async throws -> Manifest {
        loadCallCount += 1
        if loadCallCount == 1 {
            return manifest
        }
        throw FailingContentSource.LoadFailure()
    }
}
