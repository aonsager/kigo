import Foundation

// MARK: - RemoteManifestSource

/// Protocol seam for fetching the latest content manifest from a remote source.
///
/// Implementations are stateless fetchers: they fetch and decode a `Manifest`
/// on each call. Caching and state management are the responsibility of `ContentStore`.
///
/// `RemoteManifestSource` inherits `Sendable` so it is safe to pass across actor
/// boundaries under Swift 6 strict concurrency.
public protocol RemoteManifestSource: Sendable {
    /// Fetches and returns the latest manifest from the remote source.
    ///
    /// - Throws: Any `Error` raised during networking or decoding.
    /// - Returns: The decoded `Manifest`.
    func fetchLatest() async throws -> Manifest
}

// MARK: - RemoteConfig

/// Static configuration for remote manifest fetching.
@usableFromInline
enum RemoteConfig {
    /// The URL of the hosted manifest JSON.
    /// Placeholder URL — replace with the real CDN/hosting URL before production launch.
    @usableFromInline
    static let manifestURL = URL(string: "https://placeholder.kigo.example/manifest.json")!
}

// MARK: - URLSessionRemoteManifestSource

/// Production `RemoteManifestSource` implementation that fetches `manifest.json`
/// from `RemoteConfig.manifestURL` using `URLSession` and decodes it with `JSONDecoder`.
///
/// This adapter is never instantiated in tests — tests inject `FakeRemoteManifestSource`
/// via the `remoteSource` parameter on `ContentStore.init`. The adapter is thin enough
/// to be correct by inspection (no logic beyond fetch + decode).
public struct URLSessionRemoteManifestSource: RemoteManifestSource {

    private let session: URLSession
    private let decoder: JSONDecoder
    private let url: URL

    public init(
        url: URL = RemoteConfig.manifestURL,
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.url = url
        self.session = session
        self.decoder = decoder
    }

    public func fetchLatest() async throws -> Manifest {
        let (data, _) = try await session.data(from: url)
        return try decoder.decode(Manifest.self, from: data)
    }
}
