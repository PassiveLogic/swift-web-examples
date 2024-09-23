// swift-tools-version:5.9.1
import PackageDescription
let package = Package(
    name: "TokamakAppDemo",
    platforms: [.macOS(.v11), .iOS(.v13)],
    products: [
        .executable(name: "TokamakAppDemo", targets: ["TokamakAppDemo"])
    ],
    dependencies: [
        .package(url: "https://github.com/TokamakUI/Tokamak", from: "0.11.0")
    ],
    targets: [
        .executableTarget(
            name: "TokamakAppDemo",
            dependencies: [
                "TokamakAppDemoLibrary",
                .product(name: "TokamakShim", package: "Tokamak")
            ]),
        .target(
            name: "TokamakAppDemoLibrary",
            dependencies: []),
        .testTarget(
            name: "TokamakAppDemoLibraryTests",
            dependencies: ["TokamakAppDemoLibrary"]),
    ]
)
