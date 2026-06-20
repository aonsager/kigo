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
            .overlay {
                if isPresented {
                    BottomSheetOverlay(isPresented: $isPresented, content: sheetContent)
                        .transition(.opacity)
                }
            }
            .animation(KigoTheme.Motion.sheet, value: isPresented)
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

    /// Drives the slide-in: starts off-screen, animates to 0 on appear.
    @State private var hasAppeared = false

    /// Translation past which a drag-up-release dismisses.
    private let dismissThreshold: CGFloat = 60

    var body: some View {
        GeometryReader { proxy in
            let screenHeight = proxy.size.height
            // Cap the card at ~90% of screen height; content beyond that scrolls.
            let maxCardHeight = screenHeight * 0.9

            ZStack(alignment: .bottom) {
                // 1 · Dimmed backdrop — fills the screen, sits behind the card.
                //     A single gesture handles BOTH a tap (tiny translation) and a
                //     downward drag (translation.height > threshold) to dismiss.
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

                // 2 · The content-height card, bottom-anchored.
                card(maxCardHeight: maxCardHeight)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: maxCardHeight, alignment: .bottom)
                    // Slide-in from below, plus live drag offset.
                    .offset(y: hasAppeared ? dragOffset : screenHeight)
            }
        }
        .ignoresSafeArea()
        .onAppear { hasAppeared = true }
    }

    private func card(maxCardHeight: CGFloat) -> some View {
        // `ScrollView` caps the card height; when content is shorter than the
        // cap the `ScrollView` still sizes to its content, so the card hugs it.
        ScrollView {
            content()
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: maxCardHeight)
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
    }
}
