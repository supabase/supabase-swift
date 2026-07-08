// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "openapi-generator",
  platforms: [.macOS(.v13)],
  dependencies: [
    .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.5.0")
  ],
  targets: []
)
