// swift-tools-version: 6.0
import PackageDescription

// SundialKit: everything the iOS and watchOS apps share, in plain Swift so it builds and is tested
// on Linux as well as on Apple platforms.
//
//   SundialCore          astronomy, dial geometry, calendars, zodiac, settings (Foundation only)
//   SundialRender        the instrument itself, drawn through the Canvas protocol
//   SundialCoreGraphics  Canvas on Core Graphics / Core Text (Apple platforms only)
//   SundialSVG           Canvas as SVG, with PNG and font tools, for renders on any platform
//   sundial-render       command-line renders for previews, store art and comparisons

/// Swift 5 language mode: the instrument is a single-threaded, main-actor object like the Android
/// view it ports, and strict concurrency checking would add ceremony without catching anything.
let settings: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "SundialKit",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "SundialCore", targets: ["SundialCore"]),
        .library(name: "SundialRender", targets: ["SundialRender"]),
        .library(name: "SundialCoreGraphics", targets: ["SundialCoreGraphics"]),
        .executable(name: "sundial-render", targets: ["sundial-render"]),
    ],
    targets: [
        .target(name: "SundialCore", swiftSettings: settings),
        .target(name: "SundialRender", dependencies: ["SundialCore"], swiftSettings: settings),
        .target(name: "SundialCoreGraphics", dependencies: ["SundialRender"], swiftSettings: settings),
        .systemLibrary(name: "CZlib", path: "Sources/CZlib"),
        .target(name: "SundialSVG", dependencies: ["SundialRender", "CZlib"], swiftSettings: settings),
        .executableTarget(name: "sundial-render", dependencies: ["SundialSVG"], swiftSettings: settings),
        .testTarget(
            name: "SundialCoreTests",
            dependencies: ["SundialCore"],
            resources: [.copy("Resources")],
            swiftSettings: settings
        ),
        .testTarget(name: "SundialRenderTests", dependencies: ["SundialRender", "SundialSVG"], swiftSettings: settings),
    ]
)
