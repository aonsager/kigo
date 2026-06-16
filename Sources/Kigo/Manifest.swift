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
    /// Perennial mapping from `MM-DD` date keys to Kigo entries.
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
    /// Yomi (reading) of the Kigo in hiragana or rōmaji.
    public let reading: String
    /// Short prose description of the Kigo.
    public let description: String
    /// Identifier for the paired image asset.
    public let imageId: String
}

// MARK: - Ko

/// One of the 72 microseasons (七十二候), each spanning roughly 5 days.
public struct Ko: Codable, Sendable, Equatable {
    /// Kanji name of the microseason (e.g. 腐草為螢).
    public let kanji: String
    /// Yomi (reading) of the Kō name.
    public let reading: String
    /// Short English gloss (e.g. "rotten grass becomes fireflies").
    public let gloss: String
    /// Identifier of the parent Sekki this Kō belongs to.
    public let sekkiId: String
    /// Approximate active date range, stored as ISO-8601 `MM-DD` strings.
    /// e.g. { "start": "06-06", "end": "06-10" }
    /// A simple, codable representation sufficient for this milestone;
    /// precise boundary handling is deferred to later slices.
    public let dateRange: DateRange
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
    /// Yomi (reading) of the Sekki name.
    public let reading: String
    /// Short localized gloss (e.g. "春の始まり"). Required Japanese, optional English (ADR 0014).
    public let gloss: LocalizedText
    /// Prose description of the solar term. Required Japanese, optional English (ADR 0014).
    public let description: LocalizedText
}
