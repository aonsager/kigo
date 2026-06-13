import SwiftUI

/// Root content view — switches on `ContentStore.screenState` to drive the
/// three defined presentation states (slice #60).
///
/// Owns no loading or resolution logic; all mapping is in `ContentStore.screenState`.
/// Three branches:
/// - `.today(ResolvedDay)` — renders `TodayView` (warm bundled path, AC3).
/// - `.loadingPlaceholder` — renders `LoadingPlaceholderView` (AC1).
/// - `.unavailablePlaceholder` — renders `UnavailablePlaceholderView` (AC2).
struct ContentView: View {
    @Environment(ContentStore.self) private var store

    var body: some View {
        switch store.screenState {
        case .today(let resolved):
            TodayView(resolvedDay: resolved)
        case .loadingPlaceholder:
            LoadingPlaceholderView()
        case .unavailablePlaceholder:
            UnavailablePlaceholderView()
        }
    }
}

// MARK: - LoadingPlaceholderView

/// Defined non-error placeholder shown while content is loading (slice #60, AC1).
///
/// Not blank, not broken — a neutral, branded surface that the user can see
/// without confusion while the bundled manifest is being decoded.
struct LoadingPlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("読み込み中…")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("loadingPlaceholder")
        .accessibilityLabel("Loading content")
    }
}

// MARK: - UnavailablePlaceholderView

/// Defined non-error placeholder shown when content is unavailable (slice #60, AC2).
///
/// Does not crash, does not show a raw error message. A calm, non-alarming surface
/// that lets the user know content is temporarily unavailable.
struct UnavailablePlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "leaf")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("コンテンツは現在利用できません")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("unavailablePlaceholder")
        .accessibilityLabel("Content unavailable")
    }
}
