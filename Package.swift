// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sunshine",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "Sunshine", targets: ["SunshineCore", "SunshineUI"]),
        .library(name: "SunshineCore", targets: ["SunshineCore"]),
    ],
    targets: [
        .target(
            name: "SunshineCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "SunshineUI",
            dependencies: ["SunshineCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "SunshineExample",
            dependencies: ["SunshineCore", "SunshineUI"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SunshineCoreTests",
            dependencies: ["SunshineCore"]
        ),
        .testTarget(
            name: "SunshineUITests",
            dependencies: ["SunshineUI"]
        ),
    ]
)
