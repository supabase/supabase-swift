// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

var package = Package(
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
      targets: ["Supabase", "Functions", "PostgREST", "GoTrue", "Realtime", "Storage"]),
  ],
  dependencies: [
    .package(url: "https://github.com/kishikawakatsumi/KeychainAccess", from: "4.2.2"),
    .package(url: "https://github.com/WeTransfer/Mocker", from: "3.0.1"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.8.1"),
  ],
  targets: [
    .target(name: "Functions"),
    .testTarget(name: "FunctionsTests", dependencies: ["Functions", "Mocker"]),
    .target(
      name: "GoTrue",
      dependencies: [
        .product(name: "KeychainAccess", package: "KeychainAccess")
      ]
    ),
    .testTarget(
      name: "GoTrueTests",
      dependencies: [
        "GoTrue",
        "Mocker",
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
      ],
      resources: [.process("Resources")]
    ),
    .target(name: "PostgREST"),
    .testTarget(
      name: "PostgRESTTests",
      dependencies: [
        "PostgREST",
        .product(
          name: "SnapshotTesting",
          package: "swift-snapshot-testing",
          condition: .when(platforms: [.iOS, .macOS, .tvOS])
        ),
      ],
      exclude: ["__Snapshots__"]
    ),
    .testTarget(name: "PostgRESTIntegrationTests", dependencies: ["PostgREST"]),
    .target(name: "Realtime"),
    .testTarget(name: "RealtimeTests", dependencies: ["Realtime"]),
    .target(name: "Storage"),
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
