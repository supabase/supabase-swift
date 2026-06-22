<p align="center">
  <a href="https://supabase.io">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/supabase/supabase/master/packages/common/assets/images/supabase-logo-wordmark--dark.svg">
      <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/supabase/supabase/master/packages/common/assets/images/supabase-logo-wordmark--light.svg">
      <img alt="Supabase Logo" width="300" src="https://raw.githubusercontent.com/supabase/supabase/master/packages/common/assets/images/logo-preview.jpg">
    </picture>
  </a>

  <h1 align="center">Supabase Swift SDK</h1>

  <p align="center">
    <a href="https://supabase.com/docs/guides/getting-started">Guides</a>
    ·
    <a href="https://supabase.com/docs/reference/swift/introduction">Reference Docs</a>
  </p>
</p>

<div align="center">

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fsupabase%2Fsupabase-swift%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/supabase/supabase-swift)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fsupabase%2Fsupabase-swift%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/supabase/supabase-swift)
[![Coverage Status](https://coveralls.io/repos/github/supabase/supabase-swift/badge.svg?branch=main)](https://coveralls.io/github/supabase/supabase-swift?branch=main)

</div>

## Libraries

| Library        | Description                                  |
|----------------|----------------------------------------------|
| **Supabase**   | Full client — includes all libraries below   |
| **Auth**       | User authentication and session management   |
| **PostgREST**  | Query your Postgres database via REST        |
| **Realtime**   | Subscribe to database changes over WebSocket |
| **Storage**    | Manage files and objects                     |
| **Functions**  | Invoke Supabase Edge Functions               |

## Quick Start

### Requirements
- iOS 16.0+ / macOS 12.0+ / tvOS 16+ / watchOS 9+ / visionOS 1+
- Xcode 16.3+
- Swift 6.1+

> [!IMPORTANT]
> Check the [Support Policy](#support-policy) to learn when dropping Xcode, Swift, and platform versions will not be considered a **breaking change**.

### Installation

Add `supabase-swift` as a Swift Package Manager dependency:

```swift
let package = Package(
    ...
    dependencies: [
        .package(
            url: "https://github.com/supabase/supabase-swift.git",
            from: "2.0.0"
        ),
    ],
    targets: [
        .target(
            name: "YourTargetName",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift")
            ]
        )
    ]
)
```

If you're using Xcode, [use this guide](https://developer.apple.com/documentation/swift_packages/adding_package_dependencies_to_your_app) to add `supabase-swift` to your project. Use `https://github.com/supabase/supabase-swift.git` for the URL when Xcode asks.

You can also add individual libraries (`Auth`, `Realtime`, `Storage`, `PostgREST`, `Functions`) instead of the full `Supabase` product.

### Initialize the client

```swift
let client = SupabaseClient(
    supabaseURL: URL(string: "https://xyzcompany.supabase.co")!,
    supabaseKey: "your-publishable-key"
)
```

### Initialize with custom options

```swift
let client = SupabaseClient(
    supabaseURL: URL(string: "https://xyzcompany.supabase.co")!,
    supabaseKey: "your-publishable-key",
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

Additional examples are available in the [Examples](https://github.com/supabase/supabase-swift/tree/main/Examples) directory.

## Support Policy

### Xcode

We only support Xcode versions that are currently eligible for submitting apps to the App Store. Once a specific version of Xcode is no longer supported, its removal from Supabase **won't be treated as a breaking change** and will occur in a minor release.

### Swift

The minimum supported Swift version corresponds to the minor version released with the oldest-supported Xcode version. When a Swift version reaches its end of support, it will be dropped in a **minor release**, and **this won't be considered a breaking change**.

### Platforms

We maintain support for the four latest major versions of each platform, including the current version.

When a platform version is no longer supported, Supabase will drop it in a **minor release**, and **this won't count as a breaking change**. For instance, iOS 14 will no longer be supported after the release of iOS 18, allowing its removal in a minor update.

For macOS, the named yearly releases are treated as major versions for this policy, regardless of their version numbers.

> [!IMPORTANT]
> Android, Linux and Windows work but aren't officially supported, and may stop working in future versions of the library.

## Contributing

We welcome contributions! Please see the steps below.

1. Fork the repo and clone it locally.
2. Create a feature branch (`git checkout -b feature/my-feature`).
3. Make your changes and add tests.
4. Run `make format` to format Swift code.
5. Run `make PLATFORM=IOS XCODEBUILD_ARGUMENT=test xcodebuild` to verify tests pass.
6. Commit using [Conventional Commits](https://www.conventionalcommits.org/) (e.g. `feat(auth): add PKCE support`).
7. Open a pull request against `main`.

## Support

- **Documentation**: [supabase.com/docs/reference/swift](https://supabase.com/docs/reference/swift/introduction)
- **Community**: [GitHub Discussions](https://github.com/supabase/supabase/discussions)
- **Issues**: [GitHub Issues](https://github.com/supabase/supabase-swift/issues)
- **Discord**: [Supabase Discord](https://discord.supabase.com)

## License

This project is licensed under the MIT License — see the [LICENSE](./LICENSE) file for details.

---

<div align="center">

**[Website](https://supabase.com) • [Documentation](https://supabase.com/docs) • [Community](https://github.com/supabase/supabase/discussions) • [Twitter](https://twitter.com/supabase)**

</div>
