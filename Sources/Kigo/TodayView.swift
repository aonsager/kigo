import KigoCore
import SwiftUI
import UIKit

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
///
/// Slice #228 (PRD #227, C26, ADR 0022): calls the real `KigoImageSource` seam via
/// `.task`, resolving `manifest`/`resolvedDay.kigoEntry.imageId` through the
/// `imageSource` injected from the app root (see `launchImageSource` /
/// `LaunchImageSource.swift`). Whenever resolution is `nil` (both the
/// `KIGO_FAKE_IMAGE=none` fake and, today, the production path — no bundled
/// `imageBaseURL` yet), the existing gradient placeholder renders unchanged and
/// `kigo.image.placeholder` becomes present alongside `kigo.image`.
///
/// Slice #229: when resolution is non-nil (the `KIGO_FAKE_IMAGE=loaded` fake, paired
/// with `ContentView`'s `imageBaseURLOverride`), the resolved bytes are decoded via
/// `UIImage(data:)` and rendered full-bleed by `KigoPlaceholderView`'s `remoteImage`
/// parameter — the exact same frame/scaling/`kigo.image` sentinel the placeholder uses,
/// just with the fetched photo on top. `kigo.image.remote` becomes present alongside
/// `kigo.image`, and `kigo.image.placeholder` is absent — the two markers are mutually
/// exclusive.
struct TodayView: View {
    let resolvedDay: ResolvedDay
    let almanacPositions: AlmanacPositions
    let manifest: Manifest
    let imageSource: KigoImageSource

    /// Identifies which sheet is currently active. Conforms to `Identifiable` so
    /// it can drive the single `.sheet(item:)` modifier.
    private enum ActiveSheet: Identifiable {
        case almanac
        case attribution

        var id: Self { self }
    }

    @Environment(\.language) private var language
    @Environment(\.isEntitled) private var isEntitled
    @Environment(\.openPaywall) private var openPaywall

    /// Localised UI-chrome strings for the active language.
    private var chrome: ChromeStrings { ChromeStrings(language) }

    @State private var activeSheet: ActiveSheet?
    @State private var hasAppeared = false
    /// The `KigoImageSource` seam's last resolution result (slice #228). `nil` means
    /// "show the placeholder"; non-nil (slice #229) means "render this photo full-bleed".
    @State private var remoteImageData: Data?

    /// `remoteImageData` decoded into a `UIImage` (slice #229), or `nil` when there is
    /// no resolved data yet. `KigoImageSource.image(manifest:imageId:)` only ever
    /// returns bytes that already passed its own `UIImage(data:) != nil` decode gate
    /// (#213), so this decode is expected to succeed whenever `remoteImageData` is set.
    private var resolvedRemoteImage: UIImage? {
        remoteImageData.flatMap { UIImage(data: $0) }
    }

    var body: some View {
        ZStack {
            KigoTheme.canvas
                .ignoresSafeArea()

            // 1 · Full-bleed image layer — the fetched remote photo when the
            // `KigoImageSource` seam has resolved bytes (slice #229), else the
            // deterministic placeholder. `kigo.image` (the full-bleed accessibility
            // sentinel) is always present via `KigoPlaceholderView` regardless of which
            // visual renders beneath it — see its doc comment.
            KigoPlaceholderView(imageId: resolvedDay.kigoEntry.imageId,
                                accessibilityLabelText: chrome.a11yBackgroundImage,
                                remoteImage: resolvedRemoteImage)
                .opacity(hasAppeared ? 1 : 0)
                .scaleEffect(hasAppeared ? 1 : 1.05)

            // 1b · Placeholder/remote-path markers (slice #228/#229, ADR 0022): mutually
            // exclusive, present alongside `kigo.image`, proving which path the seam
            // resolved to — `kigo.image.remote` when real bytes rendered,
            // `kigo.image.placeholder` when the gradient/bundled placeholder did.
            if resolvedRemoteImage != nil {
                Color.clear
                    .accessibilityIdentifier("kigo.image.remote")
                    .accessibilityHidden(true)
            } else {
                Color.clear
                    .accessibilityIdentifier("kigo.image.placeholder")
                    .accessibilityHidden(true)
            }

            // 2 · Legibility veil — vertical gradient, denser at top and bottom.
            KigoTheme.legibilityVeil
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // 3 · Frosted plate (`kigo.scrim`) — behind the BOTTOM band rather than
            // the central text zone (the kanji column reads directly over the photo
            // + veil). A bottom-anchored `.ultraThinMaterial` band, masked to fade
            // from clear at its top into a solid frost over the panel so whatever
            // sits in the band stays legible.
            //
            // ALWAYS present, both tiers (C22 fix, PRD #189): the scrim is a free
            // element. It is never blank — Premium sees the microseason block over
            // it, Basic sees the upsell block over it (see the bottom band below).
            GeometryReader { proxy in
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(KigoTheme.frostedTint)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .black, location: 0.6),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: proxy.size.height * 0.42)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityIdentifier("kigo.scrim")
            .accessibilityHidden(true)

            // 4 · Centered sumi-ink text column.
            textColumn
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 16)

            // 5 · (i) attribution entry — top-left.
            infoEntry

            // 6 · Bottom band, over the scrim. Premium sees the microseason block
            // (readings + tappable year timeline → almanac). Basic sees the upsell
            // block (→ purchase sheet) in the same place — so the free scrim always
            // has content over it and the interaction is symmetric: tap the band,
            // a sheet rises.
            if isEntitled {
                microseasonBlock
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .opacity(hasAppeared ? 1 : 0)
            } else {
                upsellBlock
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .opacity(hasAppeared ? 1 : 0)
            }
        }
        .onAppear {
            guard !hasAppeared else { return }
            withAnimation(KigoTheme.Motion.imageReveal) { hasAppeared = true }
        }
        .task(id: resolvedDay.kigoEntry.imageId) {
            // Slice #228: the real seam call. Both the `KIGO_FAKE_IMAGE=none` fake and
            // the production `URLSessionKigoImageTransport` path (no bundled
            // `imageBaseURL` yet) resolve `nil` today — the placeholder stays exactly as
            // before; slice #229 renders the bytes when resolution is non-nil.
            remoteImageData = await imageSource.image(manifest: manifest, imageId: resolvedDay.kigoEntry.imageId)
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

            Text(resolvedDay.kigoEntry.reading.localized(for: language))
                .font(KigoFont.zenKaku(.regular, size: 17, relativeTo: .title3))
                .tracking(7)
                .padding(.leading, 7) // balance the trailing tracking so the reading stays centered
                .foregroundStyle(KigoTheme.inkReading)
                .padding(.top, 22)
                .accessibilityIdentifier("kigo.reading")

            // The meaning (description) is the paid understanding layer — Premium only.
            // For Basic the encounter stays pure: kanji + reading over the photo, with
            // the upsell living down in the bottom band (see `upsellBlock`), not here.
            if isEntitled {
                Text(resolvedDay.kigoEntry.description.localized(for: language))
                    .font(KigoFont.zenKaku(.regular, size: 14.5, relativeTo: .body))
                    .lineSpacing(12)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(KigoTheme.inkDescription)
                    .frame(maxWidth: 280)
                    .padding(.top, 30)
                    .accessibilityIdentifier("kigo.description")
            }
        }
        .padding(.horizontal, 30)
    }

    // MARK: - Upsell block (Basic — bottom band, over the scrim)

    /// The Basic-tier bottom band: sits exactly where `microseasonBlock` sits for
    /// Premium, mirroring its rhythm (chevron → serif line → quiet subline). The
    /// whole band is one tap target carrying `meaning.upsell`; tapping opens the
    /// purchase sheet via `openPaywall()` — the same gesture that opens the almanac
    /// for Premium.
    private var upsellBlock: some View {
        Button {
            openPaywall()
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(KigoTheme.textTertiary)

                Text(chrome.upsellTitle)
                    .font(KigoFont.mincho(.semibold, size: 19, relativeTo: .headline))
                    .foregroundStyle(KigoTheme.inkKo)

                Text(chrome.upsellBody)
                    .font(KigoFont.zenKaku(.regular, size: 12.5, relativeTo: .footnote))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .foregroundStyle(KigoTheme.inkReading)
                    .frame(maxWidth: 260)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("meaning.upsell")
        .accessibilityLabel(chrome.a11yUnlockMeaning)
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
                .accessibilityLabel(chrome.a11yImageAttribution)
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
                .accessibilityLabel(chrome.a11yMicroseasonTimeline(ko: almanacPositions.koYearPosition, of: almanacPositions.koYearTotal))
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
                        Text(resolvedDay.ko.reading.localized(for: language))
                            .font(KigoFont.zenKaku(.regular, size: 12.5, relativeTo: .footnote))
                            .foregroundStyle(KigoTheme.inkReading)
                            .accessibilityIdentifier("microseason.ko")
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text(resolvedDay.sekki.kanji)
                            .font(KigoFont.mincho(.medium, size: 14, relativeTo: .subheadline))
                            .foregroundStyle(KigoTheme.inkSekki)
                        Text(resolvedDay.sekki.reading.localized(for: language))
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
                        Text(chrome.seasonSpring); Spacer(); Text(chrome.seasonSummer); Spacer(); Text(chrome.seasonAutumn); Spacer(); Text(chrome.seasonWinter)
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
