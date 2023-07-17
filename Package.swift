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
    .library(
      name: "Supabase",
      targets: ["Supabase"]
    )
  ],
  dependencies: [],
  targets: [
    .target(
      name: "Supabase",
      dependencies: [
        .product(name: "GoTrue", package: "gotrue-swift"),
        .product(name: "SupabaseStorage", package: "storage-swift"),
        .product(name: "Realtime", package: "realtime-swift"),
        .product(name: "PostgREST", package: "postgrest-swift"),
        .product(name: "Functions", package: "functions-swift"),
      ]
    ),
    .testTarget(name: "SupabaseTests", dependencies: ["Supabase"]),
  ]
)

if ProcessInfo.processInfo.environment["USE_LOCAL_PACKAGES"] != nil {
  package.dependencies.append(
    contentsOf: [
      .package(path: "../gotrue-swift"),
      .package(path: "../storage-swift"),
      .package(path: "../realtime-swift"),
      .package(path: "../postgrest-swift"),
      .package(path: "../functions-swift"),
    ]
  )
} else {
  package.dependencies.append(
    contentsOf: [
      .package(
        url: "https://github.com/supabase-community/gotrue-swift",
        branch: "dependency-free"
      ),
      .package(
        url: "https://github.com/supabase-community/storage-swift.git",
        branch: "dependency-free"
      ),
      .package(url: "https://github.com/supabase-community/realtime-swift.git", from: "0.0.2"),
      .package(
        url: "https://github.com/supabase-community/postgrest-swift",
        branch: "dependency-free"
      ),
      .package(
        url: "https://github.com/supabase-community/functions-swift",
        branch: "dependency-free"
      ),
    ]
  )
}
