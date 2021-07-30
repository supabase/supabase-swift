# supabase-swift

Supabase client for swift. Mirrors the design of [supabase-js](https://github.com/supabase/supabase-js/blob/master/README.md)

## Installation

Swift Package Manager:

Add the following lines to your `Package.swift` file:
```swift
let package = Package(
    ...
    dependencies: [
        ...
        .package(name: "Supabase", url: "https://github.com/supabase/supabase-swift.git", .branch("main")),
    ],
    targets: [
        .target(
            name: "YourTargetName",
            dependencies: ["Supabase"] // Add as a dependency
        )
    ]
)
```

If you're using Xcode, [use this guide](https://developer.apple.com/documentation/swift_packages/adding_package_dependencies_to_your_app) to add `supabase-swift` to your project. Use `https://github.com/supabase/supabase-swift.git` for the url when Xcode asks.
