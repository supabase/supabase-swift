// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

let package = Package(
  name: "Supabase",
  platforms: [
    .iOS(.v13),
    .macCatalyst(.v13),
    .macOS(.v10_15),
    .watchOS(.v6),
    .tvOS(.v13),
  ],
  products: [
    .library(name: "Auth", targets: ["Auth"]),
    .library(name: "Functions", targets: ["Functions"]),
    .library(name: "PostgREST", targets: ["PostgREST"]),
    .library(name: "Realtime", targets: ["Realtime"]),
    .library(name: "Storage", targets: ["Storage"]),
    .library(name: "Supabase", targets: ["Supabase", "Functions", "PostgREST", "Auth", "Realtime", "Storage"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-crypto.git", "1.0.0" ..< "4.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.8.1"),
    .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.0.0"),
    .package(url: "https://github.com/kishikawakatsumi/KeychainAccess", from: "4.2.2"),
  ],
  targets: [
    .target(
      name: "_Helpers",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
      ]
    ),
    .testTarget(
      name: "_HelpersTests",
      dependencies: [
        .product(name: "CustomDump", package: "swift-custom-dump"),
        "_Helpers",
      ]
    ),
    .target(
      name: "Auth",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        .product(name: "Crypto", package: "swift-crypto"),
        .product(
          name: "KeychainAccess",
          package: "KeychainAccess",
          condition: .when(
            platforms: [.macOS, .iOS, .macCatalyst, .visionOS, .tvOS, .watchOS]
          )
        ),
        "_Helpers",
      ]
    ),
    .testTarget(
      name: "AuthTests",
      dependencies: [
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
        .product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay"),
        "_Helpers",
        "Auth",
        "TestHelpers",
      ],
      exclude: [
        "__Snapshots__",
      ],
      resources: [.process("Resources")]
    ),
    .target(name: "Functions", dependencies: ["_Helpers"]),
    .testTarget(
      name: "FunctionsTests",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
        .product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay"),
        "Functions",
        "TestHelpers",
      ],
      exclude: ["__Snapshots__"]
    ),
    .testTarget(
      name: "IntegrationTests",
      dependencies: [
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
        .product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay"),
        "_Helpers",
        "Auth",
        "PostgREST",
        "Realtime",
        "Storage",
        "TestHelpers",
      ],
      resources: [.process("Fixtures")]
    ),
    .target(
      name: "PostgREST",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        "_Helpers",
      ]
    ),
    .testTarget(
      name: "PostgRESTTests",
      dependencies: [
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
        "_Helpers",
        "PostgREST",
      ],
      exclude: ["__Snapshots__"]
    ),
    .target(
      name: "Realtime",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        "_Helpers",
      ]
    ),
    .testTarget(
      name: "RealtimeTests",
      dependencies: [
        .product(name: "CustomDump", package: "swift-custom-dump"),
        "PostgREST",
        "Realtime",
        "TestHelpers",
      ]
    ),
    .target(name: "Storage", dependencies: ["_Helpers"]),
    .testTarget(
      name: "StorageTests",
      dependencies: [
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay"),
        "Storage",
      ]
    ),
    .target(
      name: "Supabase",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        "Auth",
        "Functions",
        "PostgREST",
        "Realtime",
        "Storage",
      ]
    ),
    .testTarget(
      name: "SupabaseTests",
      dependencies: [
        .product(name: "CustomDump", package: "swift-custom-dump"),
        "Supabase",
      ]
    ),
    .target(
      name: "TestHelpers",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        .product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay"),
        "Auth",
      ]
    ),
  ]
)

for target in package.targets where !target.isTest {
  target.swiftSettings = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableExperimentalFeature("StrictConcurrency"),
  ]
}
