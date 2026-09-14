// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VinScreenScraper",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "VinScreenScraper", targets: ["VinScreenScraperApp"]),
        .library(name: "VINCore", targets: ["VINCore"]),
    ],
    targets: [
        .target(
            name: "VINCore",
            path: "Sources/VINCore"
        ),
        .executableTarget(
            name: "VinScreenScraperApp",
            dependencies: ["VINCore"],
            path: "Sources/VinScreenScraperApp",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("Vision"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "VINCoreTests",
            dependencies: ["VINCore"],
            path: "Tests/VINCoreTests"
        ),
    ]
)
