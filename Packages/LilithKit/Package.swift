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
        .library(name: "Networking", targets: ["Networking"]),
        .library(name: "AppFeature", targets: ["AppFeature"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.8.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.1.0"),
        .package(url: "https://github.com/apple/swift-http-types", from: "1.3.0"),
    ],
    targets: [
        .target(name: "DesignSystem"),
        // Aus der Immich-OpenAPI-Spec erzeugt (scripts/generate-api.sh). Nicht von Hand ändern.
        .target(
            name: "ImmichAPI",
            dependencies: [.product(name: "OpenAPIRuntime", package: "swift-openapi-runtime")],
            exclude: ["openapi.json", "openapi-generator-config.yaml"]
        ),
        .target(
            name: "Networking",
            dependencies: [
                "ImmichAPI",
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
            ]
        ),
        .target(name: "TimelineGrid", dependencies: ["DesignSystem"]),
        .target(name: "AppFeature", dependencies: ["DesignSystem", "Networking", "TimelineGrid"]),
        .testTarget(name: "TimelineGridTests", dependencies: ["TimelineGrid"]),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"]),
        .testTarget(
            name: "NetworkingTests",
            dependencies: [
                "Networking",
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
