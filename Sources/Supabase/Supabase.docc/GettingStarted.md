# Getting Started

Create a client, sign a user in, and make a first request to each product.

## Overview

Add the package to your project, then create one ``SupabaseClient``.

### Add the package

In Xcode, select File > Add Package Dependencies and enter
`https://github.com/supabase/supabase-swift`. In a `Package.swift` file, add the package and the
`Supabase` product:

```swift
dependencies: [
  .package(url: "https://github.com/supabase/supabase-swift", from: "3.0.0")
],
targets: [
  .target(
    name: "App",
    dependencies: [.product(name: "Supabase", package: "supabase-swift")]
  )
]
```

### Create the client

The project URL and the publishable key are in the project dashboard. The initializer throws a
``SupabaseClientError`` when the URL has no scheme or no host.

```swift
import Supabase

let supabase = try SupabaseClient(
  supabaseURL: URL(string: "https://<ref>.supabase.co")!,
  supabaseKey: "sb_publishable_…"
)
```

Create the client once and share it. It holds the session and the Realtime connection.

Use only a publishable key in an app. A secret key gives full access to the project, so it must
stay on a server.

### Sign a user in

```swift
let session = try await supabase.auth.signIn(email: email, password: password)
print(session.user.id)
```

The client stores the session and refreshes it. To show the correct screen, follow the auth
state:

```swift
for await change in supabase.auth.events() {
  switch change.event {
  case .signedIn: showHome()
  case .signedOut: showSignIn()
  default: break
  }
}
```

### Query the database

```swift
struct Todo: Codable {
  var id: Int
  var task: String
}

let todos: [Todo] = try await supabase.from("todos")
  .select()
  .order("id")
  .execute()
  .value
```

Row level security policies decide which rows the signed-in user gets.

### Upload a file

```swift
try await supabase.storage.from("avatars").upload(path: "user123.png", data: imageData)
```

### Invoke an Edge Function

```swift
struct Greeting: Decodable {
  var message: String
}

let greeting: Greeting = try await supabase.functions.invoke(
  "hello", body: .json(["name": "Ada"])
)
```

### Listen for changes

```swift
let channel = await supabase.channel("room:42")
let messages = await channel.broadcasts(event: "message")

try await channel.subscribe()
for await message in messages {
  print(message)
}
```

### Change the configuration

``SupabaseClient/Configuration`` has one group of settings for each module, and a `global`
group for all of them.

```swift
var configuration = SupabaseClient.Configuration()
configuration.database.schema = "app"
configuration.global.headers = [HTTPField.Name("x-app")!: "demo"]

let supabase = try SupabaseClient(
  supabaseURL: url, supabaseKey: key, configuration: configuration
)
```

### Handle errors

Each module throws its own error type: `AuthError`, `PostgrestError`, `StorageError`,
`FunctionsError` and `RealtimeError`. All of them conform to `SupabaseError`, and each has a
`kind` and a `code`. A `catch` clause can name a kind or a code directly:

```swift
do {
  try await supabase.from("todos").insert(todo).execute()
} catch PostgrestError.Code.uniqueViolation {
  showDuplicate()
} catch PostgrestError.Kind.transport {
  showOfflineBanner()
}
```

The kinds and codes are open sets, so a `switch` over one needs `default:`. See
<doc:EnumsAndOpenSets>.
