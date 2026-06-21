import SwiftUI

/// A reusable, content-height bottom-sheet overlay (Slice C / issue #160).
///
/// Replaces the native `.sheet` for the three Kigo modals (almanac, attribution,
/// settings/paywall). Native `.sheet` always fills most of the screen and does
/// **not** dismiss on a backdrop tap; this overlay instead:
///
/// 1. **Hugs its content** — the bottom-anchored card is only as tall as its
///    content needs. If content would exceed ~90% of screen height, an internal
///    `ScrollView` caps the card and the content scrolls inside it.
/// 2. **Dismisses on a tap OUTSIDE the card** (the dimmed backdrop).
/// 3. **Dismisses on a downward drag** — both on the backdrop (so a top→bottom
///    drag starting on the dim, as the gated dismissal UI tests perform, closes
///    it) and on the card itself (standard sheet drag-to-dismiss for good UX).
///
/// The card supplies the shared sheet surface (`KigoTheme.sheetSurface`), the
/// rounded top corners (`KigoTheme.Radius.sheet`), and (implicitly) hosts the
/// inner view's grab handle. The inner views therefore drop their now-inert
/// `.presentationBackground` / `.presentationDetents` / `.presentationDragIndicator`
/// modifiers and just render their content.
///
/// ## Identifier contract (ADR 0013)
/// The inner views keep their `Color.clear` sentinel layer carrying the root
/// identifier (`microseason.almanac`, `info.panel`, `paywall.sheet`). Because the
/// card hosts that inner content directly inside the live view hierarchy, the
/// sentinel and all its children stay queryable via
/// `app.otherElements[...]` / `app.descendants(...).matching(identifier:)` once
/// presented, and controls inside the card (e.g. `paywall.buy`) stay hittable.
extension View {
    /// Presents `content` as a content-height bottom sheet over the receiver when
    /// `isPresented` is true. Dismissal (backdrop tap, backdrop drag-down, or
    /// card drag-down) sets `isPresented` back to false.
    func bottomSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        modifier(BottomSheetModifier(isPresented: isPresented, sheetContent: content))
    }

    /// `item`-driven variant mirroring `.sheet(item:)`: the sheet is presented
    /// whenever `item` is non-nil, and dismissal sets it back to nil.
    func bottomSheet<Item: Identifiable, SheetContent: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> SheetContent
    ) -> some View {
        let isPresented = Binding<Bool>(
            get: { item.wrappedValue != nil },
            set: { if !$0 { item.wrappedValue = nil } }
        )
        return modifier(
            BottomSheetModifier(isPresented: isPresented) {
                if let value = item.wrappedValue {
                    content(value)
                }
            }
        )
    }
}

// MARK: - BottomSheetModifier

private struct BottomSheetModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder let sheetContent: () -> SheetContent

    func body(content: Content) -> some View {
        content
            // The overlay is ALWAYS mounted (it renders nothing when not
            // presented). Gating the *whole* overlay with `if isPresented` would
            // make the overlay the outermost view being inserted/removed, so
            // SwiftUI would apply a single transition to it (defaulting to a
            // fade) and the card's own grow-from-bottom transition would never
            // fire. Keeping it mounted lets the backdrop and card be the views
            // that are individually inserted/removed, so each runs its own
            // transition.
            .overlay {
                BottomSheetOverlay(isPresented: $isPresented, content: sheetContent)
            }
    }
}

// MARK: - BottomSheetOverlay

/// The dimmed backdrop + bottom-anchored card. Owns the slide-in/out offset and
/// the live drag translation for the card.
private struct BottomSheetOverlay<SheetContent: View>: View {
    @Binding var isPresented: Bool
    @ViewBuilder let content: () -> SheetContent

    /// Live downward drag offset applied to the card (never negative — the card
    /// does not rubber-band upward).
    @State private var dragOffset: CGFloat = 0

    /// Measured intrinsic height of the sheet content, so the card hugs it
    /// (capped at `maxCardHeight`, beyond which the content scrolls).
    @State private var contentHeight: CGFloat = 0

    /// Translation past which a drag-up-release dismisses.
    private let dismissThreshold: CGFloat = 60

    var body: some View {
        GeometryReader { proxy in
            let screenHeight = proxy.size.height
            // Cap the card at ~90% of screen height; content beyond that scrolls.
            let maxCardHeight = screenHeight * 0.9

            ZStack(alignment: .bottom) {
                if isPresented {
                    // 1 · Dimmed backdrop — fills the screen, sits behind the card.
                    //     A single gesture handles BOTH a tap (tiny translation) and
                    //     a downward drag (translation.height > threshold) to dismiss.
                    Color.black.opacity(0.32)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("modal.backdrop")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("Dismiss")
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    // A tap registers as a near-zero translation; a
                                    // downward drag registers as translation.height > 0.
                                    // Either dismisses (tap-outside, or top→bottom drag
                                    // that begins on the backdrop).
                                    if abs(value.translation.height) < 10
                                        && abs(value.translation.width) < 10 {
                                        dismiss()
                                    } else if value.translation.height > dismissThreshold {
                                        dismiss()
                                    }
                                }
                        )
                        // Fades in/out independently of the card's grow-from-bottom.
                        .transition(.opacity)

                    // 2 · The content-height card, bottom-anchored. It grows up from
                    //     the bottom edge on present and slides back down on dismiss.
                    card(maxCardHeight: maxCardHeight)
                        .frame(maxWidth: .infinity)
                        // Live drag offset (drag-to-dismiss); the present/dismiss
                        // animation is driven by the offset transition below.
                        .offset(y: dragOffset)
                        // Pure slide from the bottom — no fade (the card slides
                        // under the dimming backdrop, which fades on its own). A
                        // fixed `screenHeight` offset (NOT `.move(edge:)`, which
                        // moves by the view's own height = 0 on the first frame
                        // before the content height is measured) guarantees a full
                        // slide every time, including the first open of each sheet.
                        .transition(.offset(y: screenHeight))
                }
            }
            // Drives both the backdrop fade and the card's grow-from-bottom as
            // `isPresented` flips (the backdrop/card are inserted/removed here, so
            // their individual transitions run).
            .animation(KigoTheme.Motion.sheet, value: isPresented)
        }
        .ignoresSafeArea()
    }

    private func card(maxCardHeight: CGFloat) -> some View {
        // The card hugs its content: a background `GeometryReader` reports the
        // content's intrinsic height, and the `ScrollView` is pinned to
        // `min(contentHeight, maxCardHeight)`. A bare `ScrollView` is greedy — it
        // fills all offered height — but it proposes *unbounded* height to its
        // content, so the content settles at its natural size for the measurement.
        // (`ViewThatFits` can't be used here: each sheet's root carries an
        // ADR-0013 `Color.clear` sentinel, which is itself greedy, so when offered
        // a finite height the content always reports "I fit" at full height.)
        // The card's height is 0 on its very first frame (the measurement is one
        // layout pass behind), so the entrance transition must NOT be height-based
        // — see the `.offset(y: screenHeight)` transition at the call site.
        ScrollView {
            content()
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: SheetContentHeightKey.self, value: geo.size.height)
                    }
                )
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity)
        .frame(height: min(contentHeight, maxCardHeight))
        .onPreferenceChange(SheetContentHeightKey.self) { contentHeight = $0 }
        // The card surface + rounded top corners (the inner views no longer
        // supply these via `.presentationBackground`).
        .background(
            KigoTheme.sheetSurface,
            in: UnevenRoundedRectangle(
                topLeadingRadius: KigoTheme.Radius.sheet,
                topTrailingRadius: KigoTheme.Radius.sheet
            )
        )
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: KigoTheme.Radius.sheet,
                topTrailingRadius: KigoTheme.Radius.sheet
            )
        )
        .ignoresSafeArea(edges: .bottom)
        // Card drag-to-dismiss: track downward drag, release past threshold closes.
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    dragOffset = max(0, value.translation.height)
                }
                .onEnded { value in
                    if value.translation.height > dismissThreshold {
                        dismiss()
                    } else {
                        withAnimation(KigoTheme.Motion.sheet) { dragOffset = 0 }
                    }
                }
        )
    }

    private func dismiss() {
        withAnimation(KigoTheme.Motion.sheet) {
            isPresented = false
        }
        // Clear any leftover drag so the next present grows cleanly from the
        // bottom (the card is re-inserted each time the sheet opens).
        dragOffset = 0
    }
}

// MARK: - SheetContentHeightKey

/// Reports the sheet content's intrinsic height up to the card, so the card can
/// hug its content instead of letting the inner `ScrollView` fill the screen.
private struct SheetContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
