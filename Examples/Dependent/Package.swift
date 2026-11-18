// swift-tools-version:6.0
// Dependent: the smallest app that depends on AppKitCross the way a developer's own package
// does, built with a plain `swift build` on Windows, Linux and macOS (ADR-0046). On macOS the
// condition leaves Apple's SwiftUI in charge; on Windows and Linux the port's is used.
import PackageDescription

let portPlatforms: [Platform] = [.windows, .linux]

let package = Package(
    name: "Dependent",
    platforms: [.macOS(.v14)],
    dependencies: [.package(name: "AppKitCross", path: "../..")],
    targets: [
        .executableTarget(name: "Dependent", dependencies: [
            .product(name: "AppKit", package: "AppKitCross", condition: .when(platforms: portPlatforms)),
            .product(name: "SwiftUI", package: "AppKitCross", condition: .when(platforms: portPlatforms)),
        ], resources: [.copy("Greeting.txt")], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
