// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LilithKit",
    defaultLocalization: "de",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "AppFeature", targets: ["AppFeature"]),
    ],
    targets: [
        .target(name: "DesignSystem"),
        .target(name: "AppFeature", dependencies: ["DesignSystem"]),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"]),
    ],
    swiftLanguageModes: [.v6]
)
