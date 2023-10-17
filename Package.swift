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
    .library(name: "Supabase", targets: ["Supabase", "Functions", "PostgREST", "GoTrue"]),
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
      resources: [
        .process("Resources")
      ]
    ),
    .target(
      name: "PostgREST",
      dependencies: []
    ),
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
      exclude: [
        "__Snapshots__"
      ]
    ),
    .testTarget(name: "PostgRESTIntegrationTests", dependencies: ["PostgREST"]),
    .target(
      name: "Supabase",
      dependencies: [
        "GoTrue",
        .product(name: "SupabaseStorage", package: "storage-swift"),
        .product(name: "Realtime", package: "realtime-swift"),
        "PostgREST",
        "Functions",
      ]
    ),
    .testTarget(name: "SupabaseTests", dependencies: ["Supabase"]),
  ]
)

if ProcessInfo.processInfo.environment["USE_LOCAL_PACKAGES"] != nil {
  package.dependencies.append(
    contentsOf: [
      .package(path: "../storage-swift"),
      .package(path: "../realtime-swift"),
    ]
  )
} else {
  package.dependencies.append(
    contentsOf: [
      .package(
        url: "https://github.com/supabase-community/storage-swift.git",
        branch: "dependency-free"
      ),
      .package(url: "https://github.com/supabase-community/realtime-swift.git", from: "0.0.2"),
    ]
  )
}
