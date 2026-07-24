import KigoCore
import WidgetKit

// MARK: - KigoWidgetEntry
//
// Slice #69: Timeline entry model for the Kigo widget.
//
// Carries the resolved Kigo content (kanji, reading, backdrop) for a given date.
// Content fields are optional so that a placeholder / unresolved entry can be
// created without content (e.g. during first launch before the manifest loads).
//
// Slice #71 / Slice C7: The widget is ungated (ADR 0019) — the backdrop is
// always shown, unconditionally, on every resolved entry.
//
// Image pivot (Task 4): `imageId`/`showsImage` retired in favour of a
// `backdropAssetName`/`fallbackHue` pair keyed on the resolved day's Sekki
// (`SekkiBackdrop`), matching the app's Today screen (ADR 0019 supersedes
// the temporary imageId-keyed bridge from Task 2).
//
// Separated from KigoWidget.swift so that the entry model can be compiled into
// the KigoWidgetTests target without dragging in the @main entry point or SwiftUI.
public struct KigoWidgetEntry: TimelineEntry {
    public let date: Date
    /// Kanji representation of today's Kigo, or nil if unresolved.
    public let kanji: String?
    /// Yomi (reading) of today's Kigo in hiragana, or nil if unresolved.
    public let reading: String?
    /// The bundled per-Sekki backdrop asset name (`backdrop-<sekkiId>`). Always present —
    /// the widget is ungated and always shows the backdrop + Kigo (ADR 0019).
    public let backdropAssetName: String
    /// Deterministic per-Sekki fallback hue used when the asset is not yet bundled.
    public let fallbackHue: Double

    /// Convenience initialiser for the resolved case (all fields present).
    public init(date: Date, kanji: String, reading: String, backdropAssetName: String, fallbackHue: Double) {
        self.date = date
        self.kanji = kanji
        self.reading = reading
        self.backdropAssetName = backdropAssetName
        self.fallbackHue = fallbackHue
    }

    /// Unresolved / placeholder entry (content fields nil, deterministic empty backdrop).
    public init(date: Date) {
        self.date = date
        self.kanji = nil
        self.reading = nil
        self.backdropAssetName = ""
        self.fallbackHue = 0
    }
}
