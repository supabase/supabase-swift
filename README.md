# supabase-swift
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fsupabase%2Fsupabase-swift%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/supabase/supabase-swift)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fsupabase%2Fsupabase-swift%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/supabase/supabase-swift)

Supabase client for swift. Mirrors the design of [supabase-js](https://github.com/supabase/supabase-js/blob/master/README.md).

* Documentation: [https://supabase.com/docs/reference/swift/introduction](https://supabase.com/docs/reference/swift/introduction)

## Usage

Install the library using the Swift Package Manager.

```swift
let package = Package(
    ...
    dependencies: [
        ...
        .package(
            url: "https://github.com/supabase-community/supabase-swift.git",
            from: "2.0.0"
        ),
    ],
    targets: [
        .target(
            name: "YourTargetName",
            dependencies: ["Supabase"] // Add as a dependency
        )
    ]
)
```

If you're using Xcode, [use this guide](https://developer.apple.com/documentation/swift_packages/adding_package_dependencies_to_your_app) to add `supabase-swift` to your project. Use `https://github.com/supabase-community/supabase-swift.git` for the url when Xcode asks.

If you don't want the full Supabase environment, you can also add individual packages, such as `Functions`, `Auth`, `Realtime`, `Storage`, or `PostgREST`.

Then you're able to import the package and establish the connection with the database.

```swift
/// Create a single supabase client for interacting with your database
let client = SupabaseClient(supabaseURL: URL(string: "https://xyzcompany.supabase.co")!, supabaseKey: "public-anon-key")
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

## Contributing

- Fork the repo on GitHub
- Clone the project to your own machine
- Commit changes to your own branch
- Push your work back up to your fork
- Submit a Pull request so that we can review your changes and merge

## Sponsors

We are building the features of Firebase using enterprise-grade, open source products. We support existing communities wherever possible, and if the products don’t exist we build them and open source them ourselves. Thanks to these sponsors who are making the OSS ecosystem better for everyone.

[![New Sponsor](https://user-images.githubusercontent.com/10214025/90518111-e74bbb00-e198-11ea-8f88-c9e3c1aa4b5b.png)](https://github.com/sponsors/supabase)
