import WidgetKit

// MARK: - KigoWidgetEntry
//
// Slice #69: Timeline entry model for the Kigo widget.
//
// Carries the resolved Kigo content (kanji, reading, imageId) for a given date.
// Content fields are optional so that a placeholder / unresolved entry can be
// created without content (e.g. during first launch before the manifest loads).
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

    /// Convenience initialiser for the resolved case (all fields present).
    public init(date: Date, kanji: String, reading: String, imageId: String) {
        self.date = date
        self.kanji = kanji
        self.reading = reading
        self.imageId = imageId
    }

    /// Unresolved / placeholder entry (content fields nil).
    public init(date: Date) {
        self.date = date
        self.kanji = nil
        self.reading = nil
        self.imageId = nil
    }
}
