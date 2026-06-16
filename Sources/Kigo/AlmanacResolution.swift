import Foundation

// MARK: - AlmanacPositions

/// The result of resolving "where in the almanac year are we?" against the loaded `Manifest`.
///
/// Introduced in slice #106 (C11 walking skeleton) carrying the Kō year-position only.
/// Designed for extension in slices #107–#109: add Sekki year-position, day-within-Kō,
/// and Kō-within-Sekki without breaking existing callers (see ADR 0007 pattern).
///
/// `AlmanacPositions` is a value type (struct), Foundation-only, `Sendable`, and `Equatable`.
public struct AlmanacPositions: Sendable, Equatable {

    /// The 1-indexed position of the current Kō within the risshun-anchored almanac year.
    ///
    /// Ordering: the 72 Kō are sorted by `dateRange.start` (lexicographic, which equals
    /// calendar order for zero-padded MM-DD strings), then rotated so the sequence begins
    /// at 立春/risshun — the Kō whose `dateRange.start` is `"02-04"` — as per ADR 0015.
    ///
    /// Example: 梅子黄 (06-16 – 06-20) → `koYearPosition` == 27.
    public let koYearPosition: Int

    /// Total number of Kō in the manifest (always 72 for the bundled content).
    public let koYearTotal: Int

    /// The 1-indexed position of the current Sekki within the risshun-anchored almanac year.
    ///
    /// Ordering: the 24 Sekki are ordered by the earliest `dateRange.start` of their
    /// constituent Kō (lexicographic MM-DD), then rotated so the sequence begins at
    /// 立春/risshun — the Sekki whose earliest Kō starts at `"02-04"` — mirroring
    /// the same anchoring applied to the Kō ordering (ADR 0015).
    ///
    /// The current Sekki is identified via the already-resolved current Kō's `sekkiId`,
    /// avoiding a redundant date-containment pass.
    ///
    /// Example: 芒種 (Bōshu, containing 梅子黄 at 06-16) → `sekkiYearPosition` == 9.
    public let sekkiYearPosition: Int

    /// Total number of Sekki in the manifest (always 24 for the bundled content).
    public let sekkiYearTotal: Int
}

// MARK: - AlmanacResolver

/// A pure, Foundation-only resolver that maps an injected date to an `AlmanacPositions`.
///
/// The resolver is a stateless enum namespace (no stored properties) so it is
/// trivially thread-safe and requires no initialisation. Callers pass both the
/// date and the manifest explicitly, keeping the function pure and testable.
///
/// Day-key derivation delegates entirely to `DayKey.make(from:)` — the same shared
/// implementation used by `TodayResolver`.
///
/// Kō containment reuses the same predicate as `TodayResolver`:
///   `dateRange.start <= key && key <= dateRange.end`
/// with no year-wrap (see ADR 0008).
///
/// The Kō year-position is 1-indexed within the risshun-anchored 72-Kō ordering
/// (see ADR 0015 for the rationale behind risshun anchoring).
public enum AlmanacResolver {

    /// The MM-DD start of 立春 (risshun), the traditional Japanese almanac new year.
    /// The 72-Kō ordering is rotated so this Kō is at position 1.
    private static let risshunStart = "02-04"

    /// Resolves `date` against `manifest` and returns the matching `AlmanacPositions`,
    /// or `nil` if the derived day-key does not fall within any Kō in the manifest.
    ///
    /// Kō containment uses plain string comparison (`start ≤ key ≤ end`) with no
    /// year-wrap logic. See ADR 0005 and ADR 0008.
    ///
    /// The Kō year-position is computed against the risshun-anchored ordering
    /// (the 72 Kō sorted by `dateRange.start`, rotated to start at `"02-04"`).
    /// See ADR 0015.
    ///
    /// - Parameters:
    ///   - date: The date to resolve (typically from a `DateProvider`).
    ///   - manifest: The loaded `Manifest` to look up.
    /// - Returns: An `AlmanacPositions` carrying the Kō year-position, or `nil` if
    ///   the derived key falls outside all Kō ranges.
    public static func resolve(date: Date, manifest: Manifest) -> AlmanacPositions? {
        guard let key = DayKey.make(from: date) else { return nil }

        // Find the current Kō using the same containment expression as TodayResolver.
        guard let currentKo = manifest.ko.first(where: {
            $0.dateRange.start <= key && key <= $0.dateRange.end
        }) else {
            return nil
        }

        // Build the risshun-anchored ordering:
        // 1. Sort all 72 Kō by dateRange.start (lexicographic == calendar order for MM-DD).
        // 2. Find the index of the risshun Kō (dateRange.start == "02-04").
        // 3. Rotate the array so it begins at risshun.
        let sortedKo = manifest.ko.sorted { $0.dateRange.start < $1.dateRange.start }

        guard let risshunIndex = sortedKo.firstIndex(where: {
            $0.dateRange.start == risshunStart
        }) else {
            // Manifest does not contain a risshun Kō — programming error or unexpected data.
            return nil
        }

        let rotated = Array(sortedKo[risshunIndex...]) + Array(sortedKo[..<risshunIndex])

        // Find the 1-indexed position of the current Kō in the rotated ordering.
        guard let positionIndex = rotated.firstIndex(where: {
            $0.kanji == currentKo.kanji
        }) else {
            return nil
        }

        // MARK: Sekki year-position (slice #107)
        //
        // Identify the current Sekki via the already-resolved Kō's sekkiId — no second
        // date-containment pass needed.
        guard manifest.sekki.first(where: { $0.id == currentKo.sekkiId }) != nil else {
            return nil
        }

        // Build the risshun-anchored Sekki ordering:
        // 1. For each Sekki, find the earliest dateRange.start among its constituent Kō.
        // 2. Sort the 24 Sekki by that earliest start (lexicographic == calendar order for MM-DD).
        // 3. Rotate so the sequence begins at the Sekki whose earliest Kō starts at "02-04"
        //    (立春/risshun), mirroring the Kō anchoring from ADR 0015.
        let sortedSekki = manifest.sekki.sorted { lhs, rhs in
            let lhsEarliestStart = manifest.ko
                .filter { $0.sekkiId == lhs.id }
                .map { $0.dateRange.start }
                .min() ?? ""
            let rhsEarliestStart = manifest.ko
                .filter { $0.sekkiId == rhs.id }
                .map { $0.dateRange.start }
                .min() ?? ""
            return lhsEarliestStart < rhsEarliestStart
        }

        // Find the Sekki whose earliest Kō start is the risshun anchor ("02-04").
        guard let risshunSekkiIndex = sortedSekki.firstIndex(where: { sekki in
            let earliestStart = manifest.ko
                .filter { $0.sekkiId == sekki.id }
                .map { $0.dateRange.start }
                .min() ?? ""
            return earliestStart == risshunStart
        }) else {
            return nil
        }

        let rotatedSekki = Array(sortedSekki[risshunSekkiIndex...]) + Array(sortedSekki[..<risshunSekkiIndex])

        // Find the 1-indexed position of the current Sekki in the rotated ordering.
        guard let sekkiPositionIndex = rotatedSekki.firstIndex(where: {
            $0.id == currentKo.sekkiId
        }) else {
            return nil
        }

        return AlmanacPositions(
            koYearPosition: positionIndex + 1,      // 1-indexed
            koYearTotal: rotated.count,
            sekkiYearPosition: sekkiPositionIndex + 1, // 1-indexed
            sekkiYearTotal: rotatedSekki.count
        )
    }
}
