import Foundation

/// Metadata about the Kigo app, read from the built bundle at runtime.
///
/// These accessors deliberately read `Bundle.main` (the app's Info.plist as
/// baked in by the build) rather than hard-coded constants, so a test asserting
/// against them genuinely exercises the project configuration: a misconfigured
/// `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` makes the assertion fail.
enum AppInfo {
    /// The app's bundle identifier as resolved from the built bundle.
    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? ""
    }

    /// The app's human-readable display name from the built bundle's Info.plist.
    static var displayName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? ""
    }
}
