// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Supabase",
    platforms: [
        .macOS(.v10_12),
        .iOS(.v10),
        .watchOS(.v3),
    ],
    products: [
        .library(
            name: "Supabase",
            targets: ["Supabase"]),
    ],
    dependencies: [
        .package(name: "gotrue", url: "https://github.com/satishbabariya/gotrue-swift.git", .branch("main")),
    ],
    targets: [
        .target(
            name: "Supabase",
            dependencies: ["gotrue"]),
        .testTarget(
            name: "SupabaseTests",
            dependencies: ["Supabase"]),
    ]
)
