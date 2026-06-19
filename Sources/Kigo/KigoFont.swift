import SwiftUI

/// A namespace for Kigo's custom font helpers.
///
/// Provides factory methods for each bundled typeface so that callers reference
/// the font by name in a type-safe way rather than using raw string literals.
enum KigoFont {
    /// Returns a `Font` using ShipporiMincho-Regular at the given point size.
    ///
    /// The font is bundled under `Resources/Fonts/ShipporiMincho-Regular.ttf`
    /// and declared in `UIAppFonts` so UIKit/SwiftUI can resolve it by its
    /// PostScript name "ShipporiMincho-Regular".
    static func shipporiMinchoRegular(size: CGFloat, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        Font.custom("ShipporiMincho-Regular", size: size, relativeTo: textStyle)
    }

    /// Returns a `Font` using ZenKakuGothicNew-Regular at the given point size.
    ///
    /// The font is bundled under `Resources/Fonts/ZenKakuGothicNew-Regular.ttf`
    /// and declared in `UIAppFonts` so UIKit/SwiftUI can resolve it by its
    /// PostScript name "ZenKakuGothicNew-Regular". Used for UI-chrome text
    /// elements (subheadlines, body text, footnotes) throughout the app.
    static func zenKakuGothicNewRegular(size: CGFloat, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        Font.custom("ZenKakuGothicNew-Regular", size: size, relativeTo: textStyle)
    }
}
