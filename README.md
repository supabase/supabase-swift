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
        .package(name: "Supabase", url: "https://github.com/supabase/supabase-swift.git", branch: "master"), // Add the package
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

## Usage

For all requests made for supabase, you will need to initialize a `SupabaseClient` object.

```swift
let client = SupabaseClient(supabaseURL: "{ Supabase URL }", supabaseKey: "{ Supabase anonymous Key }")
```

## Contributing

- Fork the repo on GitHub
- Clone the project to your own machine
- Commit changes to your own branch
- Push your work back up to your fork
- Submit a Pull request so that we can review your changes and merge

## Sponsors

We are building the features of Firebase using enterprise-grade, open source products. We support existing communities wherever possible, and if the products don’t exist we build them and open source them ourselves. Thanks to these sponsors who are making the OSS ecosystem better for everyone.

[![New Sponsor](https://user-images.githubusercontent.com/10214025/90518111-e74bbb00-e198-11ea-8f88-c9e3c1aa4b5b.png)](https://github.com/sponsors/supabase)
