import Foundation
import UIKit

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
/// Slice #205 proved schema, seam, and transport-injection layers connect.
/// Slice #206 added the on-disk cache (miss fetches once, hit serves from disk
/// with no re-fetch). Slice #207 adds the size cap and LRU eviction below. The
/// production URLSession-backed transport is NOT built here — see slice #208.
/// Slice #213 adds the decode-validation gate: a cache-miss fetch that "succeeds"
/// at the transport level but hands back bytes that don't decode as an image is
/// treated exactly like a transport throw (nil, nothing written to the cache).
public struct KigoImageSource: Sendable {

    private let transport: KigoImageTransport
    private let cacheDirectory: URL
    private let maxCacheBytes: Int?

    /// - Parameter cacheDirectory: Directory the on-disk cache reads/writes
    ///   `<imageId>.jpg` files under. Injectable so tests can point it at a
    ///   temporary directory (mirrors the `transport` seam) and callers can
    ///   choose the appropriate app-support/caches location; this slice does not
    ///   wire a default location into production (see #206 scope notes).
    /// - Parameter maxCacheBytes: Optional cap (in bytes) on the on-disk cache's
    ///   total footprint (#207). `nil` (the default) means unbounded — existing
    ///   callers/tests from #205/#206 that don't pass this get the old behavior.
    ///   When set, a cache-miss write that pushes the directory's total size over
    ///   the cap evicts least-recently-used entries (by file modification date)
    ///   until the total is back at or under the cap.
    public init(transport: KigoImageTransport, cacheDirectory: URL, maxCacheBytes: Int? = nil) {
        self.transport = transport
        self.cacheDirectory = cacheDirectory
        self.maxCacheBytes = maxCacheBytes
    }

    /// Resolves the image bytes for `imageId` against `manifest`.
    ///
    /// Returns `nil` immediately (no fetch attempted) if `manifest.imageBaseURL`
    /// is `nil`. Otherwise checks the on-disk cache first: a hit returns the
    /// cached bytes with no transport call. A miss derives the URL, fetches
    /// through the injected transport, confirms the bytes decode as a valid image
    /// (#213), writes the result to the cache directory for next time, and returns
    /// the fetched bytes — or `nil` if the fetch throws for any reason, or if the
    /// fetched bytes fail to decode as an image (nothing is written to the cache
    /// in either failure case).
    public func image(manifest: Manifest, imageId: String) async -> Data? {
        guard let base = manifest.imageBaseURL else { return nil }
        guard let url = URL(string: "\(base)/\(imageId).jpg") else { return nil }

        let cacheFileURL = cacheFileURL(for: imageId)
        if let cached = try? Data(contentsOf: cacheFileURL) {
            touch(cacheFileURL)
            return cached
        }

        do {
            let data = try await transport.fetchData(from: url)
            // Slice #213: a cache-miss fetch that "succeeds" at the transport level
            // can still hand back bytes that aren't a real image (a broken CDN
            // response, truncated transfer, HTML error page, etc.). Validate by
            // decoding before writing anything to disk or returning to the caller —
            // an undecodable payload must fail exactly like a transport throw below
            // (nil, nothing cached), not surface as a "successful" fetch of garbage.
            guard UIImage(data: data) != nil else { return nil }
            writeToCache(data, at: cacheFileURL)
            enforceCacheCapIfNeeded()
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

    /// Marks `fileURL` as most-recently-used (#207) by bumping its
    /// modification date to now. A cache hit must do this or the entry will
    /// look stale — as old as its original write — to the next eviction pass,
    /// even though it was just accessed.
    private func touch(_ fileURL: URL) {
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: fileURL.path
        )
    }

    /// Enforces `maxCacheBytes` (#207), if configured, by deleting
    /// least-recently-used cache files — oldest file-modification-date first —
    /// until the on-disk cache directory's total footprint is at or under the
    /// cap. No-op when `maxCacheBytes` is `nil` (unbounded cache, #205/#206
    /// behavior).
    ///
    /// Recency is tracked via the filesystem's own modification date rather
    /// than a separate in-memory index: a cache-miss write naturally stamps
    /// "now", and a cache hit explicitly bumps it (see `image(manifest:imageId:)`)
    /// so a re-resolved entry counts as most-recently-used.
    private func enforceCacheCapIfNeeded() {
        guard let maxCacheBytes else { return }

        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return }

        var files: [(url: URL, date: Date, size: Int)] = entries.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let date = values.contentModificationDate,
                  let size = values.fileSize
            else { return nil }
            return (url, date, size)
        }
        files.sort { $0.date < $1.date }

        var totalSize = files.reduce(0) { $0 + $1.size }
        for file in files where totalSize > maxCacheBytes {
            if (try? FileManager.default.removeItem(at: file.url)) != nil {
                totalSize -= file.size
            }
        }
    }
}

// MARK: - URLSessionKigoImageTransport

/// Production `KigoImageTransport` implementation that fetches raw image bytes
/// via `URLSession`. Thin enough to be correct by inspection (no logic beyond
/// the fetch) — mirrors `URLSessionRemoteManifestSource`'s role for
/// `RemoteManifestSource` (see `RemoteManifestSource.swift`).
///
/// Slice #208. Not wired into `KigoImageSource`'s production configuration,
/// `TodayView`, or any launch-env/`KIGO_FAKE_IMAGE` resolver in this slice —
/// that lands in a later milestone (C26). Verified offline in
/// `KigoImageSourceAdapterTests` via a stubbed `URLProtocol` registered on the
/// adapter's own `URLSession`, so no real network call occurs in the suite.
public struct URLSessionKigoImageTransport: KigoImageTransport {

    /// Thrown when the response's HTTP status code falls outside the 2xx
    /// range (#214). A 404/500/etc. still carries a response body (an HTML
    /// error page, a JSON error envelope, ...) that `URLSession` happily hands
    /// back as "successful" data — without this check that body would be
    /// treated as fetched image bytes. `KigoImageSource` catches any thrown
    /// error and resolves to `nil`, so this composes with the existing
    /// fallback path identically to a lower-level transport failure.
    public enum TransportError: Error, Equatable {
        case nonSuccessStatusCode(Int)
    }

    private let session: URLSession

    /// - Parameter session: The `URLSession` to issue requests through.
    ///   Defaults to `.shared` for production use; tests inject a session
    ///   configured with a stubbed `URLProtocol` to stay fully offline.
    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchData(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw TransportError.nonSuccessStatusCode(httpResponse.statusCode)
        }
        return data
    }
}
