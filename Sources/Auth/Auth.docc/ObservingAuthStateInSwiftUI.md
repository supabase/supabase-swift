# Observing auth state in SwiftUI

Show the signed-in or signed-out screen, and update it when the session changes.

## Overview

``AuthClient`` is `Sendable`, not `@Observable`, so a view cannot read it as state. Use an
``AuthModel`` on iOS 17, macOS 14, tvOS 17, watchOS 10, and visionOS 1 or later. On earlier
versions, consume ``AuthClient/events()`` in `.task`.

### Use an AuthModel

Create one ``AuthModel`` for the app. Keep it in `@State` and pass it down with `.environment`.
Keep the client alive too: the model does not retain it.

```swift
let supabaseClient = try! SupabaseClient(
  supabaseURL: URL(string: "https://xyzcompany.supabase.co")!,
  supabaseKey: "your-publishable-key"
)

@main
struct MyApp: App {
  @State private var auth = AuthModel(client: supabaseClient.auth)

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(auth)
    }
  }
}

struct RootView: View {
  @Environment(AuthModel.self) private var auth

  var body: some View {
    switch auth.status {
    case .loading: ProgressView()
    case .signedIn: HomeView()
    case .signedOut: SignInView()
    }
  }
}
```

Read ``AuthModel/session``, ``AuthModel/user``, or ``AuthModel/isLoading`` when a view needs less
than the whole status.

The model carries the status only. For an event such as ``AuthEvent/passwordRecovery``, also
consume ``AuthClient/events()``.

### Share the client with an environment value

`AuthModel` does not ship an environment key, so the SDK does not import SwiftUI. To give views
the client, declare your own key with the `@Entry` macro, which needs Xcode 16 or later. Use the
same client as the model, so a sign-out in a view reaches the state the model follows.

```swift
extension EnvironmentValues {
  @Entry var supabase = supabaseClient
}

struct ProfileView: View {
  @Environment(\.supabase) private var supabase

  var body: some View {
    Button("Sign out") {
      Task { try await supabase.auth.signOut() }
    }
  }
}
```

### Support iOS 16

``AuthModel`` needs iOS 17. On iOS 16, keep the state in your own `@State` and update it from
``AuthClient/events()`` in `.task`. SwiftUI cancels the task when the view goes away, and that
ends the stream.

```swift
struct RootView: View {
  @State private var status: AuthStatus = supabaseClient.auth.status

  var body: some View {
    Group {
      switch status {
      case .loading: ProgressView()
      case .signedIn: HomeView()
      case .signedOut: SignInView()
      }
    }
    .task {
      for await change in supabaseClient.auth.events() {
        status = change.status
      }
    }
  }
}
```

The first element of the stream is always ``AuthEvent/initialSession``, so the view needs no other
setup.
