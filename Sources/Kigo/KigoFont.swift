import SwiftUI

/// A namespace for Kigo's custom font helpers.
///
/// Provides factory methods for each bundled typeface so that callers reference
/// the font by name in a type-safe way rather than using raw string literals.
///
/// Asagiri revamp: the design leans on multiple weights of each family
/// (Shippori Mincho 400–800 for the focal word, titles, prices and glosses;
/// Zen Kaku Gothic New 300/400/500 for readings, body and labels). Each weight
/// is a separate bundled `.ttf` declared in `UIAppFonts`, resolved here by its
/// PostScript name through the `Mincho` / `ZenKaku` enums. The original
/// `shipporiMinchoRegular` / `zenKakuGothicNewRegular` helpers are retained as
/// thin wrappers so existing call sites and tests keep compiling.
enum KigoFont {

    // MARK: - Weight catalogues (PostScript names)

    /// Shippori Mincho weights bundled with the app. Raw values are the exact
    /// PostScript names declared in `UIAppFonts` and resolvable via `Font.custom`.
    enum Mincho: String {
        case regular = "ShipporiMincho-Regular"
        case medium = "ShipporiMincho-Medium"
        case semibold = "ShipporiMincho-SemiBold"
        case bold = "ShipporiMincho-Bold"
        case extrabold = "ShipporiMincho-ExtraBold"
    }

    /// Zen Kaku Gothic New weights bundled with the app.
    enum ZenKaku: String {
        case light = "ZenKakuGothicNew-Light"
        case regular = "ZenKakuGothicNew-Regular"
        case medium = "ZenKakuGothicNew-Medium"
    }

    // MARK: - Weighted factories

    /// Returns a Shippori Mincho `Font` at the given weight and point size,
    /// scaling relative to `textStyle` for Dynamic Type support.
    static func mincho(_ weight: Mincho, size: CGFloat, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        Font.custom(weight.rawValue, size: size, relativeTo: textStyle)
    }

    /// Returns a Zen Kaku Gothic New `Font` at the given weight and point size,
    /// scaling relative to `textStyle` for Dynamic Type support.
    static func zenKaku(_ weight: ZenKaku, size: CGFloat, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        Font.custom(weight.rawValue, size: size, relativeTo: textStyle)
    }

    // MARK: - Back-compatible Regular helpers

    /// Returns a `Font` using ShipporiMincho-Regular at the given point size.
    ///
    /// The font is bundled under `Resources/Fonts/ShipporiMincho-Regular.ttf`
    /// and declared in `UIAppFonts` so UIKit/SwiftUI can resolve it by its
    /// PostScript name "ShipporiMincho-Regular".
    static func shipporiMinchoRegular(size: CGFloat, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        mincho(.regular, size: size, relativeTo: textStyle)
    }

    /// Returns a `Font` using ZenKakuGothicNew-Regular at the given point size.
    ///
    /// The font is bundled under `Resources/Fonts/ZenKakuGothicNew-Regular.ttf`
    /// and declared in `UIAppFonts` so UIKit/SwiftUI can resolve it by its
    /// PostScript name "ZenKakuGothicNew-Regular". Used for UI-chrome text
    /// elements (subheadlines, body text, footnotes) throughout the app.
    static func zenKakuGothicNewRegular(size: CGFloat, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        zenKaku(.regular, size: size, relativeTo: textStyle)
    }
}
