// swift-tools-version: 6.0
import CompilerPluginSupport
import PackageDescription

let package = Package(
  name: "_RealtimeTableMacros",
  platforms: [.iOS(.v17), .macOS(.v14), .tvOS(.v17), .watchOS(.v10), .visionOS(.v1)],
  products: [
    .library(name: "_RealtimeTableMacros", targets: ["_RealtimeTableMacros"]),
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "601.0.0"),
  ],
  targets: [
    .macro(
      name: "_RealtimeTableMacroPlugin",
      dependencies: [
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
      ]
    ),
    .target(
      name: "_RealtimeTableMacros",
      dependencies: [
        .target(name: "_RealtimeTableMacroPlugin"),
      ]
    ),
    .testTarget(
      name: "_RealtimeTableMacrosTests",
      dependencies: [
        .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
        "_RealtimeTableMacros",
        "_RealtimeTableMacroPlugin",
      ]
    ),
  ]
)
