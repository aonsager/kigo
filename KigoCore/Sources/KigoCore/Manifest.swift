import Foundation

// MARK: - LocalizedText

/// A localization-ready text container carrying a required Japanese value and
/// an optional English value. Decodes successfully whether or not the "en" key
/// is present, so adding English content later is a data change only (ADR 0014).
///
/// JSON shapes:
///   `{ "ja": "…" }` — Japanese only (no English yet)
///   `{ "ja": "…", "en": "…" }` — both values present
public struct LocalizedText: Codable, Sendable, Equatable {
    /// Required Japanese prose value.
    public let ja: String
    /// Optional English prose value; nil when the "en" key is absent in JSON.
    public let en: String?

    public init(ja: String, en: String? = nil) {
        self.ja = ja
        self.en = en
    }


}

// MARK: - Manifest

/// The single content document that conforms to the Contract (ADR 0001).
/// Contains the full Daily Map, the 72 Kō, and the 24 Sekki, plus a schemaVersion
/// for forward-compatible decoding.
///
/// Intentionally imports Foundation only — no SwiftUI — so the test target
/// can exercise this type directly without importing any UI framework.
// Equatable conformance is added so ContentStoreTests (slice #19) can assert
// that the loaded Manifest equals the one returned by the injected ContentSource.
// All member types are value types whose fields are all Equatable primitives,
// so synthesis is correct and safe.
public struct Manifest: Codable, Sendable, Equatable {
    /// Semantic version string (e.g. "1.0") used to detect schema drift.
    public let schemaVersion: String
    /// Monotonic integer content version, bumped each time the dataset changes.
    /// Distinct from `schemaVersion` (the shape) — this tracks the *data* so the
    /// remote-update logic (C21) can compare a fetched manifest against the bundled
    /// one without the production adapter needing to know the field exists.
    public let version: Int

    public init(
        schemaVersion: String,
        version: Int,
        dailyMap: [String: DailyMapEntry],
        ko: [Ko],
        sekki: [Sekki]
    ) {
        self.schemaVersion = schemaVersion
        self.version = version
        self.dailyMap = dailyMap
        self.ko = ko
        self.sekki = sekki
    }
    /// Absolute mapping from `2026-MM-DD` date keys to Kigo entries — one per day of
    /// 2026 (ADR 0016). Lookup uses `DayKey.absolute(from:)`; the perennial `MM-DD`
    /// keys live only in the Kō `dateRange` containment check.
    public let dailyMap: [String: DailyMapEntry]
    /// The 72 Kō (microseasons) of the traditional Japanese almanac.
    public let ko: [Ko]
    /// The 24 Sekki (solar terms).
    public let sekki: [Sekki]
}

// MARK: - DailyMapEntry

/// A single entry in the Daily Map, keyed by `MM-DD`.
public struct DailyMapEntry: Codable, Sendable, Equatable {
    /// Kanji representation of the Kigo.
    public let kanji: String
    /// Yomi (reading) of the Kigo. Required Japanese, optional English (ADR 0014).
    public let reading: LocalizedText
    /// Short prose description of the Kigo. Required Japanese, optional English (ADR 0014).
    public let description: LocalizedText
    /// Short English translation/name of the Kigo (e.g. 花見 → "cherry-blossom
    /// viewing"). English-only — the English reader's equivalent of being able to
    /// read the kanji, so it belongs to the free Encounter (shown alongside
    /// kanji + reading), not the paid Understanding (ADR 0019/0024). Optional so
    /// manifests without it still decode unchanged and older/foreign-language
    /// content resolves to no translation line (ADR 0014 forward-compat, same
    /// pattern as `LocalizedText.en`; no schemaVersion bump implied). Not a
    /// `LocalizedText`: it has no Japanese side — a Japanese reader gets meaning
    /// from the kanji itself, so the UI shows it only in English mode.
    public let translationEn: String?

    /// Explicit memberwise init so `translationEn` can default to nil — existing
    /// call sites (and the many test fixtures) that predate this field keep
    /// compiling unchanged, while Codable synthesis still decodes it when the
    /// JSON key is present (ADR 0014 forward-compat).
    public init(
        kanji: String,
        reading: LocalizedText,
        description: LocalizedText,
        translationEn: String? = nil
    ) {
        self.kanji = kanji
        self.reading = reading
        self.description = description
        self.translationEn = translationEn
    }
}

// MARK: - Ko

/// One of the 72 microseasons (七十二候), each spanning roughly 5 days.
public struct Ko: Codable, Sendable, Equatable {
    /// Kanji name of the microseason (e.g. 腐草為螢).
    public let kanji: String
    /// Yomi (reading) of the Kō name. Required Japanese, optional English (ADR 0014).
    public let reading: LocalizedText
    /// Short English gloss (e.g. "rotten grass becomes fireflies").
    public let gloss: String
    /// Identifier of the parent Sekki this Kō belongs to.
    public let sekkiId: String
    /// Approximate active date range, stored as ISO-8601 `MM-DD` strings.
    /// e.g. { "start": "06-06", "end": "06-10" }
    /// A simple, codable representation sufficient for this milestone;
    /// precise boundary handling is deferred to later slices.
    public let dateRange: DateRange
    /// Prose description of the microseason. Required Japanese, optional English (ADR 0014).
    public let description: LocalizedText
}

/// Inclusive date range expressed as `MM-DD` strings.
public struct DateRange: Codable, Sendable, Equatable {
    public let start: String
    public let end: String
}

// MARK: - Sekki

/// One of the 24 solar terms (二十四節気), each spanning roughly 15 days.
public struct Sekki: Codable, Sendable, Equatable {
    /// Stable identifier referenced by `Ko.sekkiId`.
    public let id: String
    /// Kanji name of the solar term.
    public let kanji: String
    /// Yomi (reading) of the Sekki name. Required Japanese, optional English (ADR 0014).
    public let reading: LocalizedText
    /// Short localized gloss (e.g. "春の始まり"). Required Japanese, optional English (ADR 0014).
    public let gloss: LocalizedText
    /// Prose description of the solar term. Required Japanese, optional English (ADR 0014).
    public let description: LocalizedText
}
