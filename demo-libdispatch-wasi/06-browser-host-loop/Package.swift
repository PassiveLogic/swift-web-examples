// swift-tools-version:6.2
import PackageDescription

// build.sh sets LIBDISPATCH_SWIFT_LIBS to the lib/swift_static folder of a
// libdispatch build with the Swift overlay. The Swift SDK for WASI has no
// Dispatch module, so these flags point the compiler and linker at ours.
let dispatchLibs = Context.environment["LIBDISPATCH_SWIFT_LIBS"] ?? "LIBDISPATCH_SWIFT_LIBS-is-not-set"

let package = Package(
    name: "BrowserHostLoop",
    dependencies: [
        .package(url: "https://github.com/swiftwasm/JavaScriptKit", .upToNextMinor(from: "0.58.0"))
    ],
    targets: [
        // C code: the private host-loop SPI, and work queued with the C API.
        .target(
            name: "CDispatchHost",
            cSettings: [.unsafeFlags(["-fblocks", "-I", dispatchLibs])]
        ),
        .executableTarget(
            name: "App",
            dependencies: [
                "CDispatchHost",
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
            ],
            swiftSettings: [.unsafeFlags(["-I", dispatchLibs, "-I", "\(dispatchLibs)/wasi"])],
            linkerSettings: [.unsafeFlags(["-L", "\(dispatchLibs)/wasi"])]
        ),
    ],
    // The examples share state between closures on the one thread. Swift 6
    // strict concurrency checks cannot see that, so use the Swift 5 mode.
    swiftLanguageModes: [.v5]
)
