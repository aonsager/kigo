import KigoCore
import Foundation
import UIKit

// MARK: - fakeImageTransport

/// Reads the `KIGO_FAKE_IMAGE` launch-environment variable and returns an in-memory
/// fake `KigoImageTransport`, or `nil` when the variable is absent or unrecognised
/// (indicating the production `URLSessionKigoImageTransport`-backed configuration
/// should be used).
///
/// Recognised values:
/// - `"none"`   → a transport that always throws, so `KigoImageSource.image(manifest:imageId:)`
///                resolves `nil` (the caller falls back to the gradient placeholder) with no
///                real network access.
/// - `"loaded"` (slice #229) → a transport that always succeeds with known, decodable
///                image bytes, regardless of the URL it is asked to fetch. Paired with
///                `fakeImageBaseURLOverride` below (a synthetic, non-nil `imageBaseURL`
///                substituted into the manifest at the `ContentView` layer) so the real
///                `KigoImageSource.image(manifest:imageId:)` call path — URL derivation,
///                transport fetch, decode-validation — runs end to end and resolves
///                non-nil, with no real networking.
/// - anything else (including absent) → `nil` (caller uses the production transport).
///
/// This is the injection seam (slice #228/#229, ADR 0022) that makes the Today screen's
/// placeholder-fallback AND real-image-render paths verifiable through the real,
/// reachable app: a UI test launches with `KIGO_FAKE_IMAGE=none`/`=loaded` and asserts
/// the corresponding identifiers, with no real networking. Mirrors `fakeEntitlementSource`
/// in `LaunchEntitlementProvider.swift`.
///
/// - Parameter environment: The launch-environment dictionary, typically
///   `ProcessInfo.processInfo.environment` at the app root.
/// - Returns: A fake `KigoImageTransport` for `"none"`/`"loaded"`, or `nil` when the key
///   is absent or unrecognised.
public func fakeImageTransport(environment: [String: String]) -> (any KigoImageTransport)? {
    switch environment["KIGO_FAKE_IMAGE"] {
    case "none":
        return NoBytesKigoImageTransport()
    case "loaded":
        return FixedBytesKigoImageTransport(data: fixedLoadedImageData())
    default:
        return nil
    }
}

// MARK: - fakeImageBaseURLOverride

/// Reads `KIGO_FAKE_IMAGE` and returns a synthetic `imageBaseURL` to substitute into
/// the manifest handed to `KigoImageSource.image(manifest:imageId:)`, or `nil` when no
/// substitution is needed.
///
/// The bundled manifest's `imageBaseURL` is `nil` (ADR 0022 — no real CDN is wired up
/// yet), so `KigoImageSource.image` short-circuits to `nil` before ever calling the
/// transport (`guard let base = manifest.imageBaseURL else { return nil }`). For
/// `KIGO_FAKE_IMAGE=loaded` to exercise the real call path end to end, something has to
/// stand in for that missing `imageBaseURL`. This fixed placeholder string, paired with
/// `FixedBytesKigoImageTransport` (which ignores the derived URL and always returns
/// known bytes), lets the seam resolve non-nil without touching the bundled manifest or
/// dialing any real host — `ContentView` applies it via
/// `manifestApplyingImageBaseURLOverride(_:to:)` before passing the manifest to
/// `TodayView`.
///
/// - `"loaded"` → a fixed placeholder base URL string (never actually dialed).
/// - anything else (including absent) → `nil` (no substitution; production/`"none"`
///   behavior — and the bundled manifest's real `imageBaseURL` — is unchanged).
///
/// - Parameter environment: The launch-environment dictionary, typically
///   `ProcessInfo.processInfo.environment` at the app root.
/// - Returns: A fixed placeholder base URL string for `"loaded"`, or `nil` otherwise.
public func fakeImageBaseURLOverride(environment: [String: String]) -> String? {
    environment["KIGO_FAKE_IMAGE"] == "loaded" ? "https://fake.kigo.local/loaded-images" : nil
}

// MARK: - manifestApplyingImageBaseURLOverride

/// Returns `manifest` unchanged when `override` is `nil`; otherwise returns a copy with
/// `imageBaseURL` replaced by `override` and every other field untouched.
///
/// Used by `ContentView` to feed `TodayView` a manifest whose `imageBaseURL` resolves
/// for the `KIGO_FAKE_IMAGE=loaded` seam call (see `fakeImageBaseURLOverride`), without
/// mutating the bundled manifest itself. Safe because `TodayView` uses this `manifest`
/// solely for the `KigoImageSource` seam call — all of its other rendered content comes
/// from the already-resolved `ResolvedDay`.
///
/// - Parameters:
///   - override: The synthetic `imageBaseURL` to substitute, or `nil` for no change.
///   - manifest: The manifest to copy.
/// - Returns: `manifest`, or a copy of it with `imageBaseURL` replaced by `override`.
public func manifestApplyingImageBaseURLOverride(_ override: String?, to manifest: Manifest) -> Manifest {
    guard let override else { return manifest }
    return Manifest(
        schemaVersion: manifest.schemaVersion,
        version: manifest.version,
        imageBaseURL: override,
        dailyMap: manifest.dailyMap,
        ko: manifest.ko,
        sekki: manifest.sekki
    )
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

// MARK: - FixedBytesKigoImageTransport

/// In-memory fake `KigoImageTransport` that always succeeds, returning the same fixed
/// `Data` regardless of the URL it is asked to fetch. Used by the launch resolver for
/// the `KIGO_FAKE_IMAGE=loaded` injection seam (slice #229): paired with
/// `fakeImageBaseURLOverride`'s synthetic `imageBaseURL`, this lets
/// `KigoImageSource.image(manifest:imageId:)` run its real URL-derivation and
/// decode-validation logic end to end and resolve non-nil, with no real networking.
public struct FixedBytesKigoImageTransport: KigoImageTransport {
    private let data: Data

    public init(data: Data) {
        self.data = data
    }

    public func fetchData(from url: URL) async throws -> Data {
        data
    }
}

/// Known, deterministic, decodable JPEG bytes used by the `KIGO_FAKE_IMAGE=loaded`
/// launch-env fake transport (see `fakeImageTransport`). A small solid-colour square
/// rendered at runtime via `UIGraphicsImageRenderer` — deterministic and offline, and
/// guaranteed to pass `KigoImageSource`'s `UIImage(data:) != nil` decode-validation gate
/// (#213) since it is produced by encoding a real `UIImage`.
///
/// - Returns: JPEG-encoded bytes of a fixed 64×64 solid-colour square.
public func fixedLoadedImageData() -> Data {
    let size = CGSize(width: 64, height: 64)
    let renderer = UIGraphicsImageRenderer(size: size)
    let image = renderer.image { _ in
        UIColor.systemTeal.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
    }
    // `jpegData` only fails for a malformed `UIImage`, which a renderer-produced image
    // never is — the `??` is an unreachable-in-practice defensive fallback, not a
    // realistic failure path.
    return image.jpegData(compressionQuality: 0.9) ?? Data()
}
