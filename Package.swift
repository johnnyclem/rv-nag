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
        .executableTarget(
            name: "ReviewNagger",
            dependencies: [
                .product(name: "GCDWebServer", package: "GCDWebServer")
            ],
            path: "Sources"
        )
    ]
)
