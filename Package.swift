// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "CamTwizzle",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TwizzleCore", targets: ["TwizzleCore"]),
        .executable(name: "CamTwizzle", targets: ["CamTwizzle"]),
        .executable(name: "CamTwizzleCamera", targets: ["CamTwizzleCamera"]),
        .executable(name: "twizzle", targets: ["twizzle"]),
    ],
    targets: [
        .target(
            name: "TwizzleCore",
            path: "Sources/TwizzleCore",
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("CoreImage"),
                .linkedFramework("CoreMediaIO"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Vision"),
            ]
        ),
        .executableTarget(
            name: "CamTwizzle",
            dependencies: ["TwizzleCore"],
            path: "Sources/CamTwizzle"
        ),
        .executableTarget(
            name: "CamTwizzleCamera",
            path: "Sources/CamTwizzleCamera"
        ),
        .executableTarget(
            name: "twizzle",
            dependencies: ["TwizzleCore"],
            path: "Sources/twizzle"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
