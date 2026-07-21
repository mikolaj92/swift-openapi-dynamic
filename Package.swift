// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-openapi-dynamic",
    platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v6)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "OpenAPIDynamic",
            targets: ["OpenAPIDynamic"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/mikolaj92/swift-openapi-runtime", exact: "1.12.0-tca26.2"),
        .package(url: "https://github.com/mikolaj92/swift-openapi-urlsession", exact: "1.2.0-tca26.2"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "OpenAPIDynamic",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            ]
        ),
        .testTarget(
            name: "OpenAPIDynamicTests",
            dependencies: ["OpenAPIDynamic"]
        ),
        .testTarget(
            name: "OpenAPIDynamicIntegrationTests",
            dependencies: ["OpenAPIDynamic"]
        ),
    ]
)
