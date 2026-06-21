import SwiftUI

/// Root content view — switches on `ContentStore.screenState` to drive the
/// three defined presentation states (slice #60).
///
/// Owns no loading or resolution logic; all mapping is in `ContentStore.screenState`.
/// Three branches:
/// - `.today(ResolvedDay, AlmanacPositions)` — renders `TodayView` (warm bundled path, AC3).
/// - `.loadingPlaceholder` — renders `LoadingPlaceholderView` (AC1).
/// - `.unavailablePlaceholder` — renders `UnavailablePlaceholderView` (AC2).
struct ContentView: View {
    @Environment(ContentStore.self) private var store

    var body: some View {
        switch store.screenState {
        case .today(let resolved, let positions):
            TodayView(resolvedDay: resolved, almanacPositions: positions)
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
/// Not blank, not broken — a calm, branded surface. **Asagiri revamp**: a slow
/// accent progress ring over the quiet surface with 読み込み中… set in Mincho,
/// per `Kigo Revamp.dc.html` §2.
struct LoadingPlaceholderView: View {
    var body: some View {
        ZStack {
            KigoTheme.quietSurface.ignoresSafeArea()

            VStack(spacing: 32) {
                KigoSpinner()
                Text("読み込み中…")
                    .font(KigoFont.mincho(.regular, size: 16, relativeTo: .body))
                    .tracking(2)
                    .foregroundStyle(KigoTheme.inkSekki)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("loadingPlaceholder")
        .accessibilityLabel("Loading content")
    }
}

/// A slow accent progress ring (2.5pt stroke, ~1.1s linear spin) — the prototype's
/// calm loading affordance.
private struct KigoSpinner: View {
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.85)
            .stroke(KigoTheme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .frame(width: 40, height: 40)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: spinning)
            .onAppear { spinning = true }
    }
}

// MARK: - UnavailablePlaceholderView

/// Defined non-error placeholder shown when content is unavailable (slice #60, AC2).
///
/// Does not crash, does not show a raw error message. **Asagiri revamp**: a thin
/// leaf line-icon over the quiet surface with a calm Mincho message, per §3.
struct UnavailablePlaceholderView: View {
    var body: some View {
        ZStack {
            KigoTheme.quietSurface.ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "leaf")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(KigoTheme.textTertiary)
                Text("コンテンツは現在利用できません")
                    .font(KigoFont.mincho(.regular, size: 15, relativeTo: .body))
                    .lineSpacing(7)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(KigoTheme.inkSekki)
                    .padding(.horizontal, 38)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("unavailablePlaceholder")
        .accessibilityLabel("Content unavailable")
    }
}
