// swift-tools-version: 6.1
import PackageDescription

let package = Package(
  name: "openapi-codegen",
  platforms: [.macOS(.v13)],
  products: [
    .executable(name: "openapi-codegen", targets: ["openapi-codegen"])
  ],
  dependencies: [
    .package(url: "https://github.com/mattpolzin/OpenAPIKit.git", from: "6.2.0")
  ],
  targets: [
    .target(
      name: "OpenAPICodegenCore",
      dependencies: [
        .product(name: "OpenAPIKit30", package: "OpenAPIKit")
      ]
    ),
    .executableTarget(
      name: "openapi-codegen",
      dependencies: ["OpenAPICodegenCore"]
    ),
    .testTarget(
      name: "OpenAPICodegenCoreTests",
      dependencies: ["OpenAPICodegenCore"]
    ),
    .testTarget(
      name: "openapi-codegenTests",
      dependencies: ["OpenAPICodegenCore"]
    ),
  ]
)
