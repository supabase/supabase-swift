// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

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
    .library(
      name: "Supabase",
      targets: ["Supabase"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/supabase-community/gotrue-swift", .exactItem("0.0.4")),
    .package(
      name: "SupabaseStorage", url: "https://github.com/supabase/storage-swift.git", .exact("0.0.2")
    ),
    .package(
      name: "Realtime", url: "https://github.com/supabase/realtime-swift.git", .exact("0.0.1")),
    .package(
      name: "PostgREST", url: "https://github.com/supabase/postgrest-swift", .exact("0.0.2")),
  ],
  targets: [
    .target(
      name: "Supabase",
      dependencies: [
        .product(name: "GoTrue", package: "gotrue-swift"),
        "SupabaseStorage",
        "Realtime",
        "PostgREST",
      ]
    )
  ]
)
