import SwiftUI

/// App entry point for slice #56 (fake-date override).
///
/// Owns a single `ContentStore` over `BundledContentSource` (ADR 0006:
/// "a single instance is created at the app root and injected into the
/// SwiftUI environment"). The store begins loading immediately on init
/// and the injected `ContentView` observes its state reactively.
///
/// The `DateProvider` is resolved at startup via `launchDateProvider(environment:)`,
/// which reads the `KIGO_FAKE_DATE=YYYY-MM-DD` launch-environment variable.
/// When the variable is present and well-formed the store pins "today" to that
/// date for the entire session; otherwise it falls back to `SystemDateProvider`.
/// This makes the rendered Today screen deterministic under the environment
/// override (slice #56, acceptance criterion #1).
@main
struct KigoApp: App {
    @State private var store = ContentStore(
        source: BundledContentSource(),
        dateProvider: launchDateProvider(environment: ProcessInfo.processInfo.environment)
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
