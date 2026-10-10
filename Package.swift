// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "DayDistanceCore", defaultLocalization: "zh-Hans", platforms: [.macOS(.v14)],
    products: [.library(name: "DayDistanceCore", targets: ["DayDistanceCore"])],
    targets: [.target(name: "DayDistanceCore", path: "Shared/Core", resources: [.process("Resources")]),
              .testTarget(name: "DayDistanceCoreTests", dependencies: ["DayDistanceCore"], path: "Tests", exclude: ["Fixtures"])]
)
