// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "SunshineExample",
  platforms: [
    .macOS(.v13)
  ],
  dependencies: [
    .package(name: "Sunshine", path: "../..")
  ],
  targets: [
    .executableTarget(
      name: "SunshineExample",
      dependencies: [
        .product(name: "Sunshine", package: "Sunshine")
      ],
      swiftSettings: [.swiftLanguageMode(.v6)]
    )
  ]
)
