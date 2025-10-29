# supabase-swift
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fsupabase%2Fsupabase-swift%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/supabase/supabase-swift)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fsupabase%2Fsupabase-swift%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/supabase/supabase-swift)
[![Coverage Status](https://coveralls.io/repos/github/supabase/supabase-swift/badge.svg?branch=main)](https://coveralls.io/github/supabase/supabase-swift?branch=main)

Supabase SDK for Swift. Mirrors the design of [supabase-js](https://github.com/supabase/supabase-js/blob/master/README.md).

* Documentation: [https://supabase.com/docs/reference/swift/introduction](https://supabase.com/docs/reference/swift/introduction)

## Usage

### Requirements
- iOS 16.0+ / macOS 13+ / tvOS 16+ / watchOS 9+ / visionOS 1+
- Xcode 16.0+
- Swift 6.0+

> [!IMPORTANT]
> Check the [Support Policy](#support-policy) to learn when dropping Xcode, Swift, and platform versions will not be considered a **breaking change**.

### Installation
Install the library using the Swift Package Manager.

```swift
let package = Package(
    ...
    dependencies: [
        ...
        .package(
            url: "https://github.com/supabase/supabase-swift.git",
            from: "2.0.0"
        ),
    ],
    targets: [
        .target(
            name: "YourTargetName",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift") // Add as a dependency
            ]
        )
    ]
)
```

If you're using Xcode, [use this guide](https://developer.apple.com/documentation/swift_packages/adding_package_dependencies_to_your_app) to add `supabase-swift` to your project. Use `https://github.com/supabase-community/supabase-swift.git` for the url when Xcode asks.

If you don't want the full Supabase environment, you can also add individual packages, such as `Functions`, `Auth`, `Realtime`, `Storage`, or `PostgREST`.

Then you're able to import the package and establish the connection with the database.

```swift
/// Create a single supabase client for interacting with your database
let client = SupabaseClient(
    supabaseURL: URL(string: "https://xyzcompany.supabase.co")!,
    supabaseKey: "public-anon-key"
)
```

### Initialize with custom options

```swift
let client = SupabaseClient(
    supabaseURL: URL(string: "https://xyzcompany.supabase.co")!, 
    supabaseKey: "public-anon-key",
    options: SupabaseClientOptions(
        db: .init(
            schema: "public"
        ),
        auth: .init(
            storage: MyCustomLocalStorage(),
            flowType: .pkce
        ),
        global: .init(
            headers: ["x-my-custom-header": "my-app-name"],
            session: URLSession.myCustomSession
        )
    )
)
```

Additional examples are available [here](https://github.com/supabase/supabase-swift/tree/main/Examples).

## Support Policy

This document outlines the scope of support for Xcode, Swift, and the various platforms (iOS, macOS, tvOS, watchOS, and visionOS) in Supabase.

### Xcode
We only support Xcode versions that are currently eligible for submitting apps to the App Store. Once a specific version of Xcode is no longer supported, its removal from Supabase **won't be treated as a breaking change** and will occur in a minor release.

### Swift
The minimum supported Swift version corresponds to the minor version released with the oldest-supported Xcode version. When a Swift version reaches its end of support, it will be dropped from Supabase in a **minor release**, and **this won't be considered a breaking change**.

### Platforms
We maintain support for the four latest major versions of each platform, including the current version.

When a platform version is no longer supported, Supabase will drop it in a **minor release**, and **this won't count as a breaking change**. For instance, iOS 14 will no longer be supported after the release of iOS 18, allowing its removal in a minor update.

For macOS, the named yearly releases are treated as major versions for this policy, regardless of their version numbers.

> [!IMPORTANT]
> Android, Linux and Windows works but aren't supported, and may stop working on future versions of the library.

## Contributing

- Fork the repo on GitHub
- Clone the project to your own machine
- Commit changes to your own branch
- Push your work back up to your fork
- Submit a Pull request so that we can review your changes and merge

## Sponsors

We are building the features of Firebase using enterprise-grade, open source products. We support existing communities wherever possible, and if the products don’t exist we build them and open source them ourselves. Thanks to these sponsors who are making the OSS ecosystem better for everyone.

[![New Sponsor](https://user-images.githubusercontent.com/10214025/90518111-e74bbb00-e198-11ea-8f88-c9e3c1aa4b5b.png)](https://github.com/sponsors/supabase)
