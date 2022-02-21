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
        .package(name: "Supabase", url: "https://github.com/supabase/supabase-swift.git", exact: "0.0.1"), // Add the package
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
let client = SupabaseClient(supabaseUrl: "{ Supabase URL }", supabaseKey: "{ Supabase anonymous Key }")
```
This client object will be used for all the following examples.

### Database

Query todo table for all completed todos.
```swift
struct Todo: Codable {
    var id: String = UUID().uuidString
    var label: String
    var isDone: Bool = false
}
```

```swift
let query = try client.database.from("todos")
    .select()
    .eq(column: "isDone", value: "true")
                                
query.execute { [weak self] results in
    guard let self = self else { return }

    switch results {
    case let .success(response):
        let todos = try? response.decoded(to: [Todo].self)
        print(todos)
    case let .failure(error):
        print(error.localizedDescription)
    }
}
```

Insert a todo into the database.

```swift
let todo = Todo(label: "Example todo!")

let jsonData: Data = try JSONEncoder().encode(todo)
let jsonDict: [String: Any] = try JSONSerialization.jsonObject(with: jsonData, options: .allowFragments))

client.database.from("todos")    
    .insert(values: jsonDict)
    .execute { results in
        // Handle response
    }
```

For more query examples visit [the Javascript docs](https://supabase.io/docs/reference/javascript/select) to learn more. The API design is a near 1:1 match.

Execute an RPC
```swift
do {
    try client.database.rpc(fn: "testFunction", parameters: nil).execute { result in
        // Handle result
    }
} catch {
   print("Error executing the RPC: \(error)")
}
```

### Realtime

> Realtime docs coming soon

### Auth

Sign up with email and password
```swift
client.auth.signUp(email: "test@mail.com", password: "password") { result in
    switch result {
    case let .success(session, user): print(user)
    case let .failure(error): print(error.localizedDescription)
    }
}
```

Login up with email and password
```swift
client.auth.signIn(email: "test@mail.com", password: "password") { result in
    switch result {
    case let .success(session): print(session.accessToken, session.user)
    case let .failure(error): print(error.localizedDescription)
    }
}
```

### Storage

> Storage docs coming soon


## Contributing

- Fork the repo on GitHub
- Clone the project to your own machine
- Commit changes to your own branch
- Push your work back up to your fork
- Submit a Pull request so that we can review your changes and merge

## Sponsors

We are building the features of Firebase using enterprise-grade, open source products. We support existing communities wherever possible, and if the products don’t exist we build them and open source them ourselves. Thanks to these sponsors who are making the OSS ecosystem better for everyone.

[![New Sponsor](https://user-images.githubusercontent.com/10214025/90518111-e74bbb00-e198-11ea-8f88-c9e3c1aa4b5b.png)](https://github.com/sponsors/supabase)
