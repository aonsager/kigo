import KigoCore
import Foundation

// MARK: - fakeImageTransport

/// Reads the `KIGO_FAKE_IMAGE` launch-environment variable and returns an in-memory
/// fake `KigoImageTransport`, or `nil` when the variable is absent or unrecognised
/// (indicating the production `URLSessionKigoImageTransport`-backed configuration
/// should be used).
///
/// Recognised values:
/// - `"none"` → a transport that always throws, so `KigoImageSource.image(manifest:imageId:)`
///              resolves `nil` (the caller falls back to the gradient placeholder) with no
///              real network access.
/// - anything else (including absent) → `nil` (caller uses the production transport).
///
/// This is the injection seam (slice #228, ADR 0022) that makes the Today screen's
/// placeholder-fallback path verifiable through the real, reachable app: a UI test
/// launches with `KIGO_FAKE_IMAGE=none` and asserts the placeholder identifiers,
/// without depending on the bundled manifest's `imageBaseURL` (which is `nil` today
/// anyway — the production path resolves `nil` too, for the same visible reason) or
/// any real networking. Mirrors `fakeEntitlementSource` in `LaunchEntitlementProvider.swift`.
///
/// - Parameter environment: The launch-environment dictionary, typically
///   `ProcessInfo.processInfo.environment` at the app root.
/// - Returns: A fake `KigoImageTransport` for `"none"`, or `nil` when the key is absent
///   or unrecognised.
public func fakeImageTransport(environment: [String: String]) -> (any KigoImageTransport)? {
    switch environment["KIGO_FAKE_IMAGE"] {
    case "none":
        return NoBytesKigoImageTransport()
    default:
        return nil
    }
}

// MARK: - launchImageSource

/// Resolves the `KigoImageSource` to use at app launch, reading `KIGO_FAKE_IMAGE`
/// from the launch environment.
///
/// - `=none`  → `KigoImageSource` over an in-memory fake transport that never yields
///              bytes, so resolution is always `nil` (placeholder path).
/// - absent   → `KigoImageSource` over the production `URLSessionKigoImageTransport`.
///              Since the bundled manifest carries no `imageBaseURL` yet (ADR 0022),
///              this also resolves `nil` today — expected, not a regression (slice #228
///              scope; real image bytes land in slice #229).
///
/// Both paths share the same on-disk cache directory; the cache is inert in this slice
/// since neither path ever writes to it (both resolve `nil` before any write).
///
/// - Parameter environment: The launch-environment dictionary, typically
///   `ProcessInfo.processInfo.environment` at the app root.
/// - Returns: The resolved `KigoImageSource`.
public func launchImageSource(environment: [String: String]) -> KigoImageSource {
    let transport = fakeImageTransport(environment: environment) ?? URLSessionKigoImageTransport()
    return KigoImageSource(transport: transport, cacheDirectory: defaultImageCacheDirectory())
}

/// The default on-disk cache directory for `KigoImageSource`: a `KigoImages`
/// subdirectory of the app's Caches directory (falling back to the same subdirectory
/// of the temporary directory in the unexpected case `.cachesDirectory` cannot be
/// resolved). Neither launch path in this slice writes to it — see `launchImageSource`.
private func defaultImageCacheDirectory() -> URL {
    let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
    return base.appendingPathComponent("KigoImages", isDirectory: true)
}

// MARK: - NoBytesKigoImageTransport

/// In-memory fake `KigoImageTransport` that always throws, so any caller composing it
/// through `KigoImageSource.image(manifest:imageId:)` observes a `nil` resolution.
/// Used by the launch resolver for the `KIGO_FAKE_IMAGE=none` injection seam.
public struct NoBytesKigoImageTransport: KigoImageTransport {
    public enum NoBytesError: Error {
        case noImageConfigured
    }

    public init() {}

    public func fetchData(from url: URL) async throws -> Data {
        throw NoBytesError.noImageConfigured
    }
}
