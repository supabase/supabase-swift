// swift-tools-version:6.2

import PackageDescription

let package = Package(
  name: "supabase-typegen",
  platforms: [.macOS(.v13)],
  products: [
    .executable(name: "supabase-typegen", targets: ["SupabaseTypegen"])
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-format", "604.0.0"..<"605.0.0"),
    .package(url: "https://github.com/swiftlang/swift-syntax", "604.0.0"..<"605.0.0"),
  ],
  targets: [
    .executableTarget(
      name: "SupabaseTypegen",
      dependencies: [
        .product(name: "SwiftBasicFormat", package: "swift-syntax"),
        .product(name: "SwiftFormat", package: "swift-format"),
        .product(name: "SwiftParser", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
      ]
    ),
    .testTarget(
      name: "SupabaseTypegenTests",
      dependencies: ["SupabaseTypegen"],
      exclude: ["__Goldens__"],
      resources: [.copy("Fixtures")]
    ),
  ]
)

for target in package.targets {
  target.swiftSettings = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("ImmutableWeakCaptures"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
  ]
}
