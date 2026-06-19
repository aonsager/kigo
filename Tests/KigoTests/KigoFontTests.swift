import XCTest
import SwiftUI
@testable import Kigo

final class KigoFontTests: XCTestCase {

    /// Verifies that the ShipporiMincho-Regular font is correctly bundled and declared
    /// in UIAppFonts so that UIFont can resolve it by PostScript name.
    func testShipporiMinchoRegularIsRegistered() {
        let font = UIFont(name: "ShipporiMincho-Regular", size: 17)
        XCTAssertNotNil(font, "UIFont(name:\"ShipporiMincho-Regular\", size:17) must resolve to a non-nil instance — check UIAppFonts in Info.plist and the font resource in the bundle")
        XCTAssertTrue(
            font?.fontName.contains("ShipporiMincho") == true,
            "Resolved UIFont fontName must contain \"ShipporiMincho\", got: \(font?.fontName ?? "nil")"
        )
    }

    /// Host-renders a SwiftUI Text("菖蒲") in Shippori Mincho via ImageRenderer and
    /// attaches the PNG as a keepAlways XCTAttachment — screenshot evidence that
    /// the font is registered and renderable from the bundle.
    @MainActor
    func testShipporiMinchoRegularHostRender() throws {
        let view = Text("菖蒲")
            .font(KigoFont.shipporiMinchoRegular(size: 48))
            .padding()
            .background(Color.white)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0

        let image = renderer.uiImage
        XCTAssertNotNil(image, "ImageRenderer must produce a non-nil UIImage for Text(\"菖蒲\") styled with KigoFont.shipporiMinchoRegular(size: 48)")

        if let image {
            let pngData = image.pngData()
            XCTAssertNotNil(pngData, "UIImage must produce non-nil PNG data")

            if let pngData {
                let attachment = XCTAttachment(data: pngData, uniformTypeIdentifier: "public.png")
                attachment.name = "shippori-mincho-host-render"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }
}
