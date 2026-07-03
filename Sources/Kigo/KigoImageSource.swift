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
/// This slice (#205) proved schema, seam, and transport-injection layers
/// connect. Slice #206 adds the on-disk cache below (miss fetches once, hit
/// serves from disk with no re-fetch). Eviction/size-capping and the production
/// URLSession-backed transport are NOT built here — see slices #207-#208.
public struct KigoImageSource: Sendable {

    private let transport: KigoImageTransport
    private let cacheDirectory: URL

    /// - Parameter cacheDirectory: Directory the on-disk cache reads/writes
    ///   `<imageId>.jpg` files under. Injectable so tests can point it at a
    ///   temporary directory (mirrors the `transport` seam) and callers can
    ///   choose the appropriate app-support/caches location; this slice does not
    ///   wire a default location into production (see #206 scope notes).
    public init(transport: KigoImageTransport, cacheDirectory: URL) {
        self.transport = transport
        self.cacheDirectory = cacheDirectory
    }

    /// Resolves the image bytes for `imageId` against `manifest`.
    ///
    /// Returns `nil` immediately (no fetch attempted) if `manifest.imageBaseURL`
    /// is `nil`. Otherwise checks the on-disk cache first: a hit returns the
    /// cached bytes with no transport call. A miss derives the URL, fetches
    /// through the injected transport, writes the result to the cache directory
    /// for next time, and returns the fetched bytes — or `nil` if the fetch
    /// throws for any reason (nothing is written to the cache on failure).
    public func image(manifest: Manifest, imageId: String) async -> Data? {
        guard let base = manifest.imageBaseURL else { return nil }
        guard let url = URL(string: "\(base)/\(imageId).jpg") else { return nil }

        let cacheFileURL = cacheFileURL(for: imageId)
        if let cached = try? Data(contentsOf: cacheFileURL) {
            return cached
        }

        do {
            let data = try await transport.fetchData(from: url)
            writeToCache(data, at: cacheFileURL)
            return data
        } catch {
            return nil
        }
    }

    private func cacheFileURL(for imageId: String) -> URL {
        cacheDirectory.appendingPathComponent("\(imageId).jpg")
    }

    /// Best-effort write: a failure to persist the cache file (e.g. an
    /// unwritable directory) must not fail the resolution — the caller already
    /// has the fetched bytes in hand and simply re-fetches next time.
    private func writeToCache(_ data: Data, at fileURL: URL) {
        try? FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL)
    }
}
