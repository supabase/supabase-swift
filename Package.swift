// swift-tools-version:5.10
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
    .library(name: "Supabase", targets: ["Supabase"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-crypto.git", from: "4.0.0"),
    .package(url: "https://github.com/apple/swift-http-types.git", from: "1.3.0"),
    .package(url: "https://github.com/pointfreeco/swift-clocks", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", from: "1.1.0"),
    .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.3.2"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
    .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.2.2"),
    .package(url: "https://github.com/WeTransfer/Mocker", from: "3.0.0"),
  ],
  targets: [
    .target(
      name: "Helpers",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        .product(name: "HTTPTypes", package: "swift-http-types"),
        .product(name: "Clocks", package: "swift-clocks"),
        .product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay"),
      ]
    ),
    .testTarget(
      name: "HelpersTests",
      dependencies: [
        .product(name: "CustomDump", package: "swift-custom-dump"),
        "Helpers",
      ]
    ),
    .target(
      name: "Auth",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        .product(name: "Crypto", package: "swift-crypto"),
        "Helpers",
      ]
    ),
    .testTarget(
      name: "AuthTests",
      dependencies: [
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
        .product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay"),
        "Auth",
        "Helpers",
        "SnapshotHelpers",
        "TestHelpers",
      ],
      exclude: [
        "__Snapshots__"
      ],
      resources: [.process("Resources")]
    ),
    .target(
      name: "Functions",
      dependencies: [
        "Helpers"
      ]
    ),
    .testTarget(
      name: "FunctionsTests",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
        .product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay"),
        "Functions",
        "Mocker",
        "SnapshotHelpers",
        "TestHelpers",
      ],
      exclude: [
        "__Snapshots__"
      ]
    ),
    .testTarget(
      name: "IntegrationTests",
      dependencies: [
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
        .product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay"),
        "Helpers",
        "Supabase",
        "TestHelpers",
      ],
      resources: [
        .process("Fixtures"),
        .process("supabase"),
      ]
    ),
    .target(
      name: "PostgREST",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        "Helpers",
      ]
    ),
    .testTarget(
      name: "PostgRESTTests",
      dependencies: [
        .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
        "Helpers",
        "Mocker",
        "PostgREST",
        "SnapshotHelpers",
        "TestHelpers",
      ],
      exclude: [
        "__Snapshots__"
      ]
    ),
    .target(
      name: "Realtime",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
        "Helpers",
      ]
    ),
    .testTarget(
      name: "RealtimeTests",
      dependencies: [
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
        .product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay"),
        "Realtime",
        "TestHelpers",
      ]
    ),
    .target(
      name: "Storage",
      dependencies: [
        "Helpers"
      ]
    ),
    .testTarget(
      name: "StorageTests",
      dependencies: [
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
        .product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay"),
        "Mocker",
        "SnapshotHelpers",
        "TestHelpers",
        "Storage",
      ],
      exclude: [
        "__Snapshots__"
      ],
      resources: [
        .copy("sadcat.jpg"),
        .process("Fixtures"),
      ]
    ),
    .target(
      name: "Supabase",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
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
        .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
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
    .target(
      name: "SnapshotHelpers",
      dependencies: [
        .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
        "Mocker",
        "TestHelpers",
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
