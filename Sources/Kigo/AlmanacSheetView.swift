import SwiftUI

/// The almanac sheet presented when the user taps `microseason.timeline` on the Today screen.
///
/// Introduced in slice #123 (C13). **Asagiri revamp**: rebuilt to the two-section
/// almanac from `Kigo Revamp.dc.html` §5 — a 候 (Kō) section above a 節気 (Sekki)
/// section, each with a year-position counter, a thin segmented progress gauge, and
/// Japanese prose. All copy binds to real manifest fields (`Ko` / `Sekki`); no prose
/// is fabricated.
///
/// Accessibility identifiers (ADR 0013 Color.clear sentinel pattern for the root container):
/// - `microseason.almanac` — root Color.clear layer (ZStack sentinel)
/// - `microseason.koPosition` — Text showing e.g. "27 / 72"
/// - `microseason.dayGauge` — day-within-Kō gauge
/// - `microseason.koDescription` — Text showing ko.description.ja
/// - `microseason.sekkiPosition` / `microseason.sekkiGauge` / `microseason.sekkiDescription`
///   — added with the revamp's Sekki section (additive; existing identifiers unchanged).
struct AlmanacSheetView: View {
    let almanacPositions: AlmanacPositions
    let ko: Ko
    let sekki: Sekki

    @Environment(\.language) private var language

    var body: some View {
        ZStack {
            // ADR 0013: Color.clear sentinel — applies the root identifier only to this layer.
            Color.clear
                .accessibilityIdentifier("microseason.almanac")

            VStack(alignment: .leading, spacing: 0) {
                    GrabHandle()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                        .padding(.bottom, 22)

                    // MARK: 候 — Kō section
                    sectionLabel("候", counter: "\(almanacPositions.koYearPosition) / \(almanacPositions.koYearTotal)",
                                 counterID: "microseason.koPosition")

                    HStack(alignment: .firstTextBaseline, spacing: 13) {
                        Text(ko.kanji)
                            .font(KigoFont.mincho(.bold, size: 27, relativeTo: .title))
                            .foregroundStyle(KigoTheme.inkKo)
                        Text(ko.reading.localized(for: language))
                            .font(KigoFont.zenKaku(.regular, size: 14, relativeTo: .subheadline))
                            .foregroundStyle(KigoTheme.inkReading)
                    }
                    .padding(.top, 13)

                    AlmanacGauge(value: almanacPositions.dayWithinKo, total: almanacPositions.koRangeLength)
                        .padding(.top, 16)
                        .accessibilityIdentifier("microseason.dayGauge")
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Day \(almanacPositions.dayWithinKo) of \(almanacPositions.koRangeLength) in this microseason")

                    Text(ko.description.localized(for: language))
                        .font(KigoFont.zenKaku(.light, size: 14, relativeTo: .body))
                        .lineSpacing(13)
                        .foregroundStyle(KigoTheme.bodyProse)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 13)
                        .accessibilityIdentifier("microseason.koDescription")

                    Divider()
                        .overlay(KigoTheme.hairline)
                        .padding(.vertical, 22)

                    // MARK: 節気 — Sekki section
                    sectionLabel("節気", counter: "\(almanacPositions.sekkiYearPosition) / \(almanacPositions.sekkiYearTotal)",
                                 counterID: "microseason.sekkiPosition")

                    HStack(alignment: .firstTextBaseline, spacing: 13) {
                        Text(sekki.kanji)
                            .font(KigoFont.mincho(.bold, size: 23, relativeTo: .title2))
                            .foregroundStyle(KigoTheme.inkKo)
                        Text(sekki.reading.localized(for: language))
                            .font(KigoFont.zenKaku(.regular, size: 14, relativeTo: .subheadline))
                            .foregroundStyle(KigoTheme.inkReading)
                    }
                    .padding(.top, 13)

                    Text(sekki.gloss.localized(for: language))
                        .font(KigoFont.mincho(.medium, size: 14, relativeTo: .subheadline))
                        .foregroundStyle(KigoTheme.gloss)
                        .padding(.top, 9)

                    AlmanacGauge(value: almanacPositions.koWithinSekki, total: almanacPositions.koWithinSekkiTotal)
                        .padding(.top, 16)
                        .accessibilityIdentifier("microseason.sekkiGauge")
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Kō \(almanacPositions.koWithinSekki) of \(almanacPositions.koWithinSekkiTotal) in this solar term")

                    Text(sekki.description.localized(for: language))
                        .font(KigoFont.zenKaku(.light, size: 14, relativeTo: .body))
                        .lineSpacing(13)
                        .foregroundStyle(KigoTheme.bodyProse)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 13)
                        .accessibilityIdentifier("microseason.sekkiDescription")
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Section label

    private func sectionLabel(_ title: String, counter: String, counterID: String) -> some View {
        HStack {
            Text(title)
                .font(KigoFont.zenKaku(.medium, size: 10.5, relativeTo: .caption2))
                .tracking(4)
                .foregroundStyle(KigoTheme.textTertiary)
            Spacer()
            Text(counter)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(1)
                .foregroundStyle(KigoTheme.textTertiary)
                .accessibilityIdentifier(counterID)
        }
    }
}

// MARK: - AlmanacGauge

/// A thin baseline rule with evenly-spaced tick marks and a rounded accent fill
/// from 0 → `value`/`total`. Mirrors the prototype's segmented progress bars.
private struct AlmanacGauge: View {
    let value: Int
    let total: Int

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fraction = total > 0 ? min(max(Double(value) / Double(total), 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(KigoTheme.accentTrack)
                    .frame(height: 2)

                // Segment dividers (total - 1 internal ticks).
                if total > 1 {
                    ForEach(1..<total, id: \.self) { i in
                        Rectangle()
                            .fill(KigoTheme.tickInactive)
                            .frame(width: 1, height: 9)
                            .offset(x: width * CGFloat(i) / CGFloat(total) - 0.5)
                    }
                }

                Capsule()
                    .fill(KigoTheme.accent)
                    .frame(width: max(width * fraction, 5), height: 5)
            }
            .frame(height: 13, alignment: .center)
        }
        .frame(height: 13)
    }
}

// MARK: - GrabHandle

/// The 38×5 rounded grab indicator used at the top of bottom sheets.
struct GrabHandle: View {
    var body: some View {
        Capsule()
            .fill(KigoTheme.tickInactive)
            .frame(width: 38, height: 5)
    }
}
