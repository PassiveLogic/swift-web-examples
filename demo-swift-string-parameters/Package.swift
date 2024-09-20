// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Demo",
    dependencies: [
        // For building wasm:
        .package(url: "https://github.com/swiftwasm/carton", from: "1.0.0"),

        // For JavaScript interoperation:
        .package(url: "https://github.com/swiftwasm/JavaScriptKit", from: "0.20.0"),
    ],
    targets: [
        .executableTarget(
            name: "Demo",
            dependencies: [
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
            ]
        )
    ]
)
