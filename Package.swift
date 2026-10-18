// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Kitbag",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [
    .library(name: "KitbagCore", targets: ["KitbagCore"])
  ],
  targets: [
    .target(name: "KitbagCore"),
    .testTarget(name: "KitbagCoreTests", dependencies: ["KitbagCore"]),
  ]
)
