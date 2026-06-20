import SwiftUI

/// Today screen — renders the Kigo kanji, hiragana reading, prose description,
/// and the current Microseason (Kō and Sekki) for the resolved date.
///
/// Extended in slice #57 to add reading (`kigo.reading`) and description
/// (`kigo.description`) beneath the kanji. The view takes the already-resolved
/// `ResolvedDay` as input and performs no loading or date resolution itself.
///
/// Extended in slice #58 to add the Microseason section:
/// - `microseason.ko`: The Kō reading (hiragana) as the primary label.
/// - `microseason.sekki`: The parent Sekki reading (hiragana) as a secondary label.
///
/// Extended in slice #59 to add a full-bleed deterministic placeholder image behind
/// the text content (`kigo.image`).
///
/// Extended in slice #122/#123 to add the `microseason.timeline` affordance that
/// presents `AlmanacSheetView`; slice #128 added the `info.entry` attribution panel;
/// slice #132 consolidated the sheets onto a single `.sheet(item:)`; slice #154 added
/// the `kigo.scrim` legibility plate and moved the gear to the top-right.
///
/// **Asagiri revamp.** The visual language is rebuilt to the "morning mist" direction
/// from `Kigo Revamp.dc.html`: a full-bleed image, a vertical legibility veil and a
/// radially-feathered frosted plate (`kigo.scrim`), a centered sumi-ink Mincho text
/// column (90pt kanji), and a bottom-anchored microseason block — the Kō/Sekki readings
/// (still `microseason.ko` / `microseason.sekki`, kō above sekki) over a 72-tick
/// year timeline with four season-tint bands, the whole strip tappable as
/// `microseason.timeline`. The text column and image animate in once on appear.
///
/// Accessibility contract preserved exactly: `microseason.ko` / `microseason.sekki`
/// carry the hiragana readings as standalone static texts (not nested inside the
/// timeline `Button`, which would merge them), so the pinned-text UI assertions hold.
struct TodayView: View {
    let resolvedDay: ResolvedDay
    let almanacPositions: AlmanacPositions

    /// Identifies which sheet is currently active. Conforms to `Identifiable` so
    /// it can drive the single `.sheet(item:)` modifier.
    private enum ActiveSheet: Identifiable {
        case almanac
        case attribution

        var id: Self { self }
    }

    @State private var activeSheet: ActiveSheet?
    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            KigoTheme.canvas
                .ignoresSafeArea()

            // 1 · Full-bleed placeholder image — derived deterministically from imageId.
            KigoPlaceholderView(imageId: resolvedDay.kigoEntry.imageId)
                .opacity(hasAppeared ? 1 : 0)
                .scaleEffect(hasAppeared ? 1 : 1.05)

            // 2 · Legibility veil — vertical gradient, denser at top and bottom.
            KigoTheme.legibilityVeil
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // 3 · Frosted plate (`kigo.scrim`) — a feathered `.ultraThinMaterial` that
            // frosts only the central text zone and fades to clear photo at the edges.
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(KigoTheme.frostedTint)
                .mask(
                    GeometryReader { proxy in
                        RadialGradient(
                            stops: [
                                .init(color: .black, location: 0.34),
                                .init(color: .clear, location: 0.76),
                            ],
                            center: UnitPoint(x: 0.5, y: 0.48),
                            startRadius: 0,
                            endRadius: max(proxy.size.width, proxy.size.height) * 0.7
                        )
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                )
                .ignoresSafeArea()
                .accessibilityIdentifier("kigo.scrim")
                .accessibilityHidden(true)

            // 4 · Centered sumi-ink text column.
            textColumn
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 16)

            // 5 · (i) attribution entry — top-left.
            infoEntry

            // 6 · Bottom microseason block — readings + tappable year timeline.
            microseasonBlock
                .frame(maxHeight: .infinity, alignment: .bottom)
                .opacity(hasAppeared ? 1 : 0)
        }
        .onAppear {
            guard !hasAppeared else { return }
            withAnimation(KigoTheme.Motion.imageReveal) { hasAppeared = true }
        }
        .bottomSheet(item: $activeSheet) { sheet in
            switch sheet {
            case .almanac:
                AlmanacSheetView(
                    almanacPositions: almanacPositions,
                    ko: resolvedDay.ko,
                    sekki: resolvedDay.sekki
                )
            case .attribution:
                AttributionPanelView(attribution: resolvedDay.kigoEntry.attribution)
            }
        }
    }

    // MARK: - Text column

    private var textColumn: some View {
        VStack(spacing: 0) {
            Text(resolvedDay.kigoEntry.kanji)
                .font(KigoFont.mincho(.extrabold, size: 90, relativeTo: .largeTitle))
                .tracking(1.8)
                .foregroundStyle(KigoTheme.inkKanji)
                .shadow(color: KigoTheme.kanjiShadow, radius: 3, x: 0, y: 1)
                .accessibilityIdentifier("kigo.kanji")

            Text(resolvedDay.kigoEntry.reading)
                .font(KigoFont.zenKaku(.regular, size: 17, relativeTo: .title3))
                .tracking(7)
                .padding(.leading, 7) // balance the trailing tracking so the reading stays centered
                .foregroundStyle(KigoTheme.inkReading)
                .padding(.top, 22)
                .accessibilityIdentifier("kigo.reading")

            Text(resolvedDay.kigoEntry.description)
                .font(KigoFont.zenKaku(.regular, size: 14.5, relativeTo: .body))
                .lineSpacing(12)
                .multilineTextAlignment(.center)
                .foregroundStyle(KigoTheme.inkDescription)
                .frame(maxWidth: 280)
                .padding(.top, 30)
                .accessibilityIdentifier("kigo.description")
        }
        .padding(.horizontal, 30)
    }

    // MARK: - Info entry (top-left)

    private var infoEntry: some View {
        VStack {
            HStack {
                Button {
                    activeSheet = .attribution
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(KigoTheme.inkReading)
                        .frame(width: KigoTheme.Radius.entryCircle, height: KigoTheme.Radius.entryCircle)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(KigoTheme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("info.entry")
                .accessibilityLabel("Image attribution")
                .padding(.leading, 22)
                .padding(.top, 16)

                Spacer()
            }
            Spacer()
        }
    }

    // MARK: - Bottom microseason block

    private var microseasonBlock: some View {
        // The whole bottom band — from just above the chevron down through the
        // season labels — is a single tap target that opens the almanac. A clear,
        // band-filling Button carries `microseason.timeline` + `.contentShape`, and
        // the visual VStack is overlaid with `.allowsHitTesting(false)` so taps fall
        // through to the Button while the reading Texts stay in the a11y tree.
        // (A SwiftUI Button merges its child Texts into one a11y element, so the
        // readings must NOT be descendants of the Button — kō.minY < sekki.minY.)
        // The visual content drives the band's height; the full-band tap target is a
        // `Color.clear` Button laid *behind* it (as a background) so the tappable area
        // hugs the band instead of expanding to fill the whole screen — which would
        // overlap the top-corner `info.entry` / `paywall.entry` controls and steal
        // their taps (Slice C: it did, opening the almanac on an info.entry tap).
        timelineVisual
            .background {
                Button {
                    activeSheet = .almanac
                } label: {
                    Color.clear
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("microseason.timeline")
                .accessibilityLabel("Microseason timeline: Kō \(almanacPositions.koYearPosition) of \(almanacPositions.koYearTotal)")
            }
            .padding(.bottom, 28)
    }

    /// The non-interactive visual content of the microseason band (chevron, readings,
    /// year-timeline strip). Extracted so the tap target can be sized to it.
    private var timelineVisual: some View {
        ZStack(alignment: .bottom) {
            // Visual content — non-interactive so taps reach the background Button.
            VStack(spacing: 12) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(KigoTheme.textTertiary)

                // Kō (primary) above Sekki (secondary).
                VStack(spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text(resolvedDay.ko.kanji)
                            .font(KigoFont.mincho(.semibold, size: 19, relativeTo: .headline))
                            .foregroundStyle(KigoTheme.inkKo)
                        Text(resolvedDay.ko.reading)
                            .font(KigoFont.zenKaku(.regular, size: 12.5, relativeTo: .footnote))
                            .foregroundStyle(KigoTheme.inkReading)
                            .accessibilityIdentifier("microseason.ko")
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text(resolvedDay.sekki.kanji)
                            .font(KigoFont.mincho(.medium, size: 14, relativeTo: .subheadline))
                            .foregroundStyle(KigoTheme.inkSekki)
                        Text(resolvedDay.sekki.reading)
                            .font(KigoFont.zenKaku(.regular, size: 11.5, relativeTo: .caption))
                            .foregroundStyle(KigoTheme.textSecondary)
                            .accessibilityIdentifier("microseason.sekki")
                    }
                }

                // Year timeline visual.
                VStack(spacing: 8) {
                    MicroseasonTimelineStrip(
                        position: almanacPositions.koYearPosition,
                        total: almanacPositions.koYearTotal
                    )
                    .frame(height: 18)

                    HStack {
                        Text("春"); Spacer(); Text("夏"); Spacer(); Text("秋"); Spacer(); Text("冬")
                    }
                    .font(KigoFont.zenKaku(.regular, size: 10, relativeTo: .caption2))
                    .tracking(2)
                    .foregroundStyle(KigoTheme.textTertiary)
                }
                .padding(.horizontal, 30)
                .padding(.top, 4)
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - MicroseasonTimelineStrip

/// The resting year timeline: 72 thin ticks (one per Kō) spanning the full width,
/// today's Kō lit taller in the accent colour, over four faint season-tint bands
/// (春 / 夏 / 秋 / 冬, 25% each).
private struct MicroseasonTimelineStrip: View {
    /// 1-indexed Kō position within the risshun-anchored year (1...total).
    let position: Int
    let total: Int

    var body: some View {
        ZStack(alignment: .bottom) {
            // Four season bands behind the ticks.
            HStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { i in
                    KigoTheme.seasonBands[i]
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))

            // 72 ticks, evenly distributed; today's Kō lit and taller.
            GeometryReader { proxy in
                let count = max(total, 1)
                let lit = max(1, min(position, count)) - 1
                HStack(spacing: 0) {
                    ForEach(0..<count, id: \.self) { i in
                        let isLit = (i == lit)
                        Capsule()
                            .fill(isLit ? KigoTheme.accent : KigoTheme.tickInactive)
                            .frame(width: 1.5, height: isLit ? proxy.size.height : proxy.size.height * 0.5)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .frame(height: proxy.size.height, alignment: .bottom)
            }
        }
    }
}
