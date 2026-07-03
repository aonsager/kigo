import Foundation

// MARK: - KigoImageTransport

/// Protocol seam for fetching raw image bytes from a URL. Mirrors the
/// injectable-seam convention used by `RemoteManifestSource`/
/// `EntitlementTransactionSource` elsewhere in this codebase: the seam exists
/// so `KigoImageSource`'s URL-derivation and nil-fallback logic can be
/// exercised headlessly, with an in-memory fake, and no real networking.
///
/// This slice (#205, the walking skeleton) does not ship a production
/// URLSession-backed conformance — that lands in a later slice (#208).
public protocol KigoImageTransport: Sendable {
    /// Fetches and returns the raw bytes at `url`.
    /// - Throws: Any `Error` raised during the fetch.
    func fetchData(from url: URL) async throws -> Data
}

// MARK: - KigoImageSource

/// Derives a day's remote image URL from the manifest's `imageBaseURL` +
/// `imageId` convention (ADR 0022: `imageBaseURL + "/" + imageId + ".jpg"`)
/// and fetches its bytes through an injected `KigoImageTransport`.
///
/// Nil-safe throughout, by design: a `nil` `imageBaseURL` resolves to `nil`
/// immediately with no transport call, and any transport failure resolves to
/// `nil` rather than throwing — callers fall back to the gradient placeholder
/// (ADR 0022) either way, with no error-handling burden pushed onto them.
///
/// This is the thinnest path proving schema, seam, and transport-injection
/// layers connect (slice #205). On-disk caching and the production
/// URLSession-backed transport are NOT built here — see slices #206-#208.
public struct KigoImageSource: Sendable {

    private let transport: KigoImageTransport

    public init(transport: KigoImageTransport) {
        self.transport = transport
    }

    /// Resolves the image bytes for `imageId` against `manifest`.
    ///
    /// Returns `nil` immediately (no fetch attempted) if `manifest.imageBaseURL`
    /// is `nil`. Otherwise derives the URL and requests it from the injected
    /// transport, returning `nil` if that fetch throws for any reason.
    public func image(manifest: Manifest, imageId: String) async -> Data? {
        guard let base = manifest.imageBaseURL else { return nil }
        guard let url = URL(string: "\(base)/\(imageId).jpg") else { return nil }
        do {
            return try await transport.fetchData(from: url)
        } catch {
            return nil
        }
    }
}
