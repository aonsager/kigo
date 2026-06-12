import Foundation

// MARK: - ContentSource

/// Protocol seam for loading the content manifest (ADR 0001).
///
/// Implementations are stateless loaders: they fetch and decode a `Manifest`
/// on each call. Caching and state management are the responsibility of the
/// `ContentStore` (a later slice, C3 #19–#21); this type only models the
/// data-retrieval boundary.
///
/// `ContentSource` inherits `Sendable` so it is safe to pass across actor
/// boundaries; Swift 6 strict concurrency requires this when a value of
/// protocol type is used in async contexts.
public protocol ContentSource: Sendable {
    /// Loads and returns the content manifest.
    ///
    /// - Throws: Any `Error` raised during I/O or decoding.
    /// - Returns: The decoded `Manifest`.
    func load() async throws -> Manifest
}

// MARK: - BundledContentSource

/// Production `ContentSource` implementation that reads `manifest.json` from
/// the app bundle and decodes it into a `Manifest`.
///
/// The resource is expected to be bundled in the **Kigo app target** (see
/// `project.yml` resources). In the test host the app bundle is `Bundle.main`,
/// which is the same bundle that `ManifestValidationTests` uses.
public struct BundledContentSource: ContentSource {

    public init() {}

    public func load() async throws -> Manifest {
        // Use Bundle(for:) via a private class anchor so that the lookup works
        // correctly both in the production app (Bundle.main) and in any future
        // test context where the bundle hierarchy may differ.
        // For the current project the test host IS the Kigo app, so Bundle.main
        // resolves the resource; the class anchor is a future-safe fallback.
        let bundle = Bundle(for: _BundleAnchor.self)

        guard let url = bundle.url(forResource: "manifest", withExtension: "json")
                     ?? Bundle.main.url(forResource: "manifest", withExtension: "json") else {
            throw BundledContentSourceError.resourceNotFound("manifest.json not found in bundle")
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Manifest.self, from: data)
    }
}

// MARK: - Private helpers

/// Private class used solely as an anchor for `Bundle(for:)` so the bundle
/// lookup is tied to the module that ships `manifest.json`, even if the call
/// site is in a different module.
private final class _BundleAnchor {}

/// Errors specific to `BundledContentSource`.
public enum BundledContentSourceError: Error, Sendable {
    case resourceNotFound(String)
}
