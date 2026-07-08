import KigoCore
import WidgetKit

// MARK: - KigoWidgetEntry
//
// Slice #69: Timeline entry model for the Kigo widget.
//
// Carries the resolved Kigo content (kanji, reading, imageId) for a given date.
// Content fields are optional so that a placeholder / unresolved entry can be
// created without content (e.g. during first launch before the manifest loads).
//
// Slice #71: Added `showsImage: Bool` — the view layer uses it to decide whether
// to render the Kigo image. Since ADR 0019 inverted monetization off the widget
// (Slice C7), `WidgetTimelineBuilder` sets it unconditionally `true` on every
// resolved entry — there is no longer an entitlement gate.
//
// Separated from KigoWidget.swift so that the entry model can be compiled into
// the KigoWidgetTests target without dragging in the @main entry point or SwiftUI.
public struct KigoWidgetEntry: TimelineEntry {
    public let date: Date
    /// Kanji representation of today's Kigo, or nil if unresolved.
    public let kanji: String?
    /// Yomi (reading) of today's Kigo in hiragana, or nil if unresolved.
    public let reading: String?
    /// Identifier for the paired image asset, or nil if unresolved.
    public let imageId: String?
    /// Whether the widget should reveal the Kigo image. Since ADR 0019 the widget
    /// no longer gates on entitlement, so `WidgetTimelineBuilder` sets this
    /// unconditionally `true` on resolved entries (`false` only for the unresolved
    /// placeholder).
    public let showsImage: Bool

    /// Convenience initialiser for the resolved case (all fields present).
    public init(date: Date, kanji: String, reading: String, imageId: String, showsImage: Bool = true) {
        self.date = date
        self.kanji = kanji
        self.reading = reading
        self.imageId = imageId
        self.showsImage = showsImage
    }

    /// Unresolved / placeholder entry (content fields nil, image hidden).
    public init(date: Date) {
        self.date = date
        self.kanji = nil
        self.reading = nil
        self.imageId = nil
        self.showsImage = false
    }
}
