// swift-tools-version: 6.0
// KigoCore — Kigo's simulator-free domain logic (see docs/kigocore-migration-plan.md).
// Foundation/Observation only; anything importing SwiftUI/UIKit/WidgetKit stays in
// the app target. Tests run host-side via `scripts/xctimeout 300 swift test
// --package-path KigoCore` — no CoreSimulator anywhere in the stack.
import PackageDescription

let package = Package(
    name: "KigoCore",
    platforms: [
        .iOS("26.0"),
        // macOS floor is only for host-side `swift test`; 15 covers Observation.
        .macOS("15.0"),
    ],
    products: [
        .library(name: "KigoCore", targets: ["KigoCore"])
    ],
    targets: [
        .target(name: "KigoCore"),
        .testTarget(name: "KigoCoreTests", dependencies: ["KigoCore"]),
    ]
)
