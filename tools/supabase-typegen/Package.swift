// swift-tools-version:6.2
// A package of its own, not a product of the root one: SwiftPM resolves every dependency of every
// product a package vends, so swift-format here would be fetched by every app that depends on
// `Supabase` and would narrow its swift-syntax to the one major swift-format pins.

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
    // `CamelToSnake.swift` is a symlink to the `@Table` macro's own source, so the generator and
    // the macro derive column names with the same function.
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

// The root package's settings, so the generator is held to the same rules as the SDK.
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
