import SwiftUI

/// Root content view for slice #55 (walking skeleton).
///
/// Observes the injected `ContentStore` state. On `.loaded(Manifest)`, resolves
/// the current date through `TodayResolver` and renders `TodayView`. Loading and
/// unavailable states show minimal placeholder text; full treatment is a later slice.
struct ContentView: View {
    @Environment(ContentStore.self) private var store

    var body: some View {
        switch store.state {
        case .loading:
            Text("Loading…")
        case .loaded(let manifest):
            if let resolved = TodayResolver.resolve(date: Date(), manifest: manifest) {
                TodayView(resolvedDay: resolved)
            } else {
                Text("No entry for today")
            }
        case .unavailable:
            Text("Content unavailable")
        }
    }
}
