// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Supabase",
    products: [
        .library(
            name: "Supabase",
            targets: ["Supabase"]
        ),
    ],
    dependencies: [
        .package(name: "GoTrue", url: "https://github.com/supabase/gotrue-swift.git", .branch("main")),
        .package(name: "SupabaseStorage", url: "https://github.com/supabase/storage-swift.git", .branch("main")),
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
