// swift-tools-version:6.3
import PackageDescription

// build.sh sets LIBDISPATCH_SWIFT_LIBS to the lib/swift_static folder of a
// libdispatch build with the Swift overlay. The Swift SDK for WASI has no
// Dispatch module, so these flags point the compiler and linker at ours.
let dispatchLibs = Context.environment["LIBDISPATCH_SWIFT_LIBS"] ?? "LIBDISPATCH_SWIFT_LIBS-is-not-set"

let package = Package(
    name: "SingleThreadedDemo",
    platforms: [.macOS(.v15)],
    dependencies: [
        // ElementaryUI 0.7.0 is the last release for Swift 6.3.
        .package(url: "https://github.com/elementary-swift/elementary-ui", exact: "0.7.0"),
        .package(url: "https://github.com/swiftwasm/JavaScriptKit", .upToNextMinor(from: "0.58.0")),
        // ElementaryUI 0.7.0 builds with swift-collections 1.6. Version 1.7
        // moved APIs that it uses.
        .package(url: "https://github.com/apple/swift-collections", .upToNextMinor(from: "1.6.0")),
    ],
    targets: [
        // C code: the private host-loop SPI, and a block queued with the C API.
        .target(
            name: "CDispatchHost",
            cSettings: [.unsafeFlags(["-fblocks", "-I", dispatchLibs])]
        ),
        .executableTarget(
            name: "App",
            dependencies: [
                "CDispatchHost",
                .product(name: "ElementaryUI", package: "elementary-ui"),
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
            ],
            swiftSettings: [.unsafeFlags(["-I", dispatchLibs, "-I", "\(dispatchLibs)/wasi"])],
            linkerSettings: [.unsafeFlags(["-L", "\(dispatchLibs)/wasi"])]
        ),
    ],
    swiftLanguageModes: [.v5]
)
