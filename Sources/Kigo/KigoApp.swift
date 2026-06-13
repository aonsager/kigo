import SwiftUI

/// App entry point for slice #55 (walking skeleton).
///
/// Owns a single `ContentStore` over `BundledContentSource` (ADR 0006:
/// "a single instance is created at the app root and injected into the
/// SwiftUI environment"). The store begins loading immediately on init
/// and the injected `ContentView` observes its state reactively.
@main
struct KigoApp: App {
    @State private var store = ContentStore(source: BundledContentSource())

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
