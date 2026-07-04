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

    /// Explicit bundle override for callers whose manifest.json does not live
    /// in a bundle this module can discover on its own. Needed since the move
    /// into KigoCore: `Bundle(for:)` on a class in this module no longer
    /// resolves to the *client's* bundle, and `Bundle.main` only covers
    /// processes whose main bundle carries the manifest (the app and the
    /// widget appex — but NOT a hostless .xctest bundle like KigoWidgetTests,
    /// which must inject `Bundle(for: Self.self)`).
    private let bundle: Bundle?

    public init(bundle: Bundle? = nil) {
        self.bundle = bundle
    }

    public func load() async throws -> Manifest {
        // Lookup order: injected client bundle → this module's bundle (via a
        // private class anchor) → the process main bundle. In the production
        // app and widget-extension processes Bundle.main carries manifest.json,
        // so the zero-argument form keeps working there.
        let anchorBundle = Bundle(for: _BundleAnchor.self)

        guard let url = bundle?.url(forResource: "manifest", withExtension: "json")
                     ?? anchorBundle.url(forResource: "manifest", withExtension: "json")
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
