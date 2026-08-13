// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "MarginBuild",
  platforms: [.macOS(.v15)],
  products: [
    .executable(name: "margin-build", targets: ["MarginBuild"])
  ],
  targets: [
    .executableTarget(name: "MarginBuild")
  ]
)
