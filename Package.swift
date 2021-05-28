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
        .package(name: "GoTrue", url: "https://github.com/satishbabariya/gotrue-swift.git", .revision("7294ec73db53c2b66a0142a9e6d9a56fcf5d3d3a")),
        .package(name: "SupabaseStorage", url: "https://github.com/satishbabariya/storage-swift.git", .revision("48961a9c08700d842a88da800cc3243c9538a8e3")),

    ],
    targets: [
        .target(
            name: "Supabase",
            dependencies: ["GoTrue", "SupabaseStorage"]
        ),
        .testTarget(
            name: "SupabaseTests",
            dependencies: ["Supabase"]
        ),
    ]
)
