// swift-tools-version:5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

var dependencies: [Package.Dependency] = [
  .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.8.1"),
  .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.0.0"),
  .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", from: "1.0.0"),
  .package(url: "https://github.com/apple/swift-crypto.git", "1.0.0" ..< "3.0.0"),
]

var goTrueDependencies: [Target.Dependency] = [
  "_Helpers",
  .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
  .product(name: "Crypto", package: "swift-crypto"),
]

#if !os(Windows) && !os(Linux)
dependencies += [
  .package(url: "https://github.com/kishikawakatsumi/KeychainAccess", from: "4.2.2"),
]
goTrueDependencies += [
  .product(name: "KeychainAccess", package: "KeychainAccess"),
]
#endif

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
    .library(name: "Auth", targets: ["Auth"]),
    .library(name: "PostgREST", targets: ["PostgREST"]),
    .library(name: "Realtime", targets: ["Realtime"]),
    .library(name: "Storage", targets: ["Storage"]),
    .library(
      name: "Supabase",
      targets: ["Supabase", "Functions", "PostgREST", "Auth", "Realtime", "Storage"]
    ),
  ],
  dependencies: dependencies,
  targets: [
    .target(
      name: "_Helpers",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
      ]
    ),
    .target(name: "Functions", dependencies: ["_Helpers"]),
    .testTarget(
      name: "FunctionsTests",
      dependencies: [
        "Functions",
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
      ]
    ),
    .target(
      name: "Auth",
      dependencies: goTrueDependencies
    ),
    .testTarget(
      name: "AuthTests",
      dependencies: [
        "Auth",
        "_Helpers",
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
        .product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay"),
      ],
      exclude: [
        "__Snapshots__",
      ],
      resources: [.process("Resources")]
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
        "PostgREST",
        "_Helpers",
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
      ],
      exclude: ["__Snapshots__"]
    ),
    .testTarget(name: "PostgRESTIntegrationTests", dependencies: ["PostgREST"]),
    .target(
      name: "Realtime",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        "_Helpers",
      ]
    ),
    .testTarget(name: "RealtimeTests", dependencies: ["Realtime"]),
    .target(name: "Storage", dependencies: ["_Helpers"]),
    .testTarget(name: "StorageTests", dependencies: ["Storage"]),
    .target(
      name: "Supabase",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        "Auth",
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
    .enableUpcomingFeature("StrictConcurrency=complete"),
  ]
}
