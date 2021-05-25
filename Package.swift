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
            targets: ["Supabase"]
        ),
    ],
    dependencies: [
        .package(name: "gotrue", url: "https://github.com/satishbabariya/gotrue-swift.git", .branch("main")),
        .package(name: "SupabaseStorage", url: "https://github.com/satishbabariya/storage-swift.git", .revision("fc718b30956303cc098caf7e4ad27035b89022d5")),

    ],
    targets: [
        .target(
            name: "Supabase",
            dependencies: ["gotrue", "SupabaseStorage"]
        ),
        .testTarget(
            name: "SupabaseTests",
            dependencies: ["Supabase"]
        ),
    ]
)
