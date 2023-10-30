// swift-tools-version:5.8
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
    .library(name: "Functions", targets: ["Functions"]),
    .library(name: "GoTrue", targets: ["GoTrue"]),
    .library(name: "PostgREST", targets: ["PostgREST"]),
    .library(name: "Realtime", targets: ["Realtime"]),
    .library(name: "Storage", targets: ["Storage"]),
    .library(
      name: "Supabase",
      targets: ["Supabase", "Functions", "PostgREST", "GoTrue", "Realtime", "Storage"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/kishikawakatsumi/KeychainAccess", from: "4.2.2"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.8.1"),
    .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.0.0"),
  ],
  targets: [
    .target(name: "_Helpers"),
    .target(name: "Functions"),
    .testTarget(name: "FunctionsTests", dependencies: ["Functions"]),
    .target(
      name: "GoTrue",
      dependencies: [
        "_Helpers",
        .product(name: "KeychainAccess", package: "KeychainAccess"),
      ]
    ),
    .testTarget(
      name: "GoTrueTests",
      dependencies: [
        "GoTrue",
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
        .product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay"),
      ],
      resources: [.process("Resources")]
    ),
    .target(name: "PostgREST"),
    .testTarget(
      name: "PostgRESTTests",
      dependencies: [
        "PostgREST",
        "_Helpers",
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
      ],
      exclude: ["__Snapshots__"]
    ),
    .testTarget(name: "PostgRESTIntegrationTests", dependencies: ["PostgREST"]),
    .target(name: "Realtime", dependencies: ["_Helpers"]),
    .testTarget(name: "RealtimeTests", dependencies: ["Realtime"]),
    .target(name: "Storage", dependencies: ["_Helpers"]),
    .testTarget(name: "StorageTests", dependencies: ["Storage"]),
    .target(
      name: "Supabase",
      dependencies: [
        "GoTrue",
        "Storage",
        "Realtime",
        "PostgREST",
        "Functions",
      ]
    ),
    .testTarget(name: "SupabaseTests", dependencies: ["Supabase"]),
  ]
)

for target in package.targets where !target.isTest {
  target.swiftSettings = [
    .enableUpcomingFeature("StrictConcurrency=complete")
  ]
}
