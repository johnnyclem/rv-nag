// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ReviewNagger",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/yene/GCDWebServer.git", from: "3.5.0"),
    ],
    targets: [
        // Pure logic (models, webhook parsing/auth) so it can be unit tested.
        .target(
            name: "ReviewNaggerCore",
            path: "Sources/ReviewNaggerCore"
        ),
        .executableTarget(
            name: "ReviewNagger",
            dependencies: [
                "ReviewNaggerCore",
                .product(name: "GCDWebServer", package: "GCDWebServer")
            ],
            path: "Sources/ReviewNagger"
        ),
        .testTarget(
            name: "ReviewNaggerCoreTests",
            dependencies: ["ReviewNaggerCore"],
            path: "Tests/ReviewNaggerCoreTests"
        )
    ]
)
