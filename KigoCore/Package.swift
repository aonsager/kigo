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
        .library(name: "KigoCore", targets: ["KigoCore"]),
        // Shared ContentSource fakes, importable by BOTH the package's host-side
        // tests and the app's sim-lane test bundles (test targets can't import
        // each other, so the fakes live in a library product).
        .library(name: "KigoCoreTestSupport", targets: ["KigoCoreTestSupport"]),
    ],
    targets: [
        .target(name: "KigoCore"),
        .target(name: "KigoCoreTestSupport", dependencies: ["KigoCore"]),
        .testTarget(name: "KigoCoreTests", dependencies: ["KigoCore", "KigoCoreTestSupport"]),
    ]
)
