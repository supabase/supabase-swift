# Auth and Swift Concurrency

Know which actor each Auth API runs on, and which types you can share across actors.

## Overview

Auth is built for Swift 6 language mode with the `NonisolatedNonsendingByDefault` upcoming
feature. You can call it from the main actor, from your own actor, or from a detached task, and
the compiler checks that you pass nothing unsafe across an actor boundary.

The rule is simple: an Auth method that is `async` and not tied to an actor runs on the actor of
its caller. It does not hop to a background executor. The slow parts, such as the network request,
the Keychain read, and the session bookkeeping, run on other executors and your actor suspends at
the `await`. A call from the main actor does not block it.

### Share the types

Every type that you pass in or get back is `Sendable`:

- ``AuthClient`` is a `final class` that is `Sendable`. It is a facade over state that the client
  guards itself, so you can keep one in a global, capture it in a task, or hand it to any actor.
- ``Session``, ``User``, ``AuthStatus``, and ``AuthChange`` are value types that are `Sendable`.
- ``AuthStorage`` and ``WebAuthPresenter`` are `Sendable` protocols. A type that you write to
  conform to them must be `Sendable` too.

```swift
let supabase = try SupabaseClient(
  supabaseURL: URL(string: "https://xyzcompany.supabase.co")!,
  supabaseKey: "your-publishable-key"
)

actor Uploader {
  func upload(_ data: Data) async throws {
    // `supabase` is Sendable, so an actor can use it.
    let session = try await supabase.auth.session()
    // `Session` is Sendable, so it can leave the actor.
    await report(userID: session.user.id)
  }
}
```

### Know where each API runs

| API | Where it runs |
| --- | --- |
| ``AuthClient/status``, ``AuthClient/events()`` | Synchronous and not tied to an actor. Call them from anywhere, with no `await`. They return at once. ``AuthClient/events()`` only starts the first read of storage in the background, when the client has not read it yet. |
| ``AuthClient/signIn(email:password:captchaToken:)``, ``AuthClient/session()``, ``AuthClient/handleRedirect(_:)``, ``AuthClient/signOut(scope:)``, and the other `async` methods of ``AuthClient`` | The actor of the caller. The request and the bookkeeping run on other executors. |
| ``KeychainStorage`` reads and writes | A background executor. The methods are `@concurrent`, so Keychain I/O never blocks the caller. |
| ``WebAuthPresenter/authenticate(url:callbackScheme:)`` and ``ClosurePresenter`` | The main actor. The client awaits it, so the sign-in page opens on the main thread whichever actor called ``AuthClient/signInWithOAuth(_:options:presenter:)``. |
| ``AuthModel`` | The main actor. |

``AuthClient`` is not `@MainActor`, so a view model or a service on any actor can own it. Only the
types that touch UI are tied to the main actor.

### Call Auth from the main actor

Because the methods run on the caller's actor, a main-actor view model can call them directly and
update its state after the `await`, with no `MainActor.run` and no `Task.detached`.

```swift
@MainActor @Observable
final class SignInViewModel {
  var errorMessage: String?

  func signIn(email: String, password: String) async {
    do {
      try await supabase.auth.signIn(email: email, password: password)
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
```

``AuthModel`` is `@MainActor` and follows the client on its own. It updates after the client has
changed, so right after an `await` on a sign-in, read ``AuthClient/status`` for the state the
client holds now. See <doc:ObservingAuthStateInSwiftUI>.

### Consume the event stream

``AuthClient/events()`` returns an `AsyncStream` that never throws. The `for await` body runs on
the actor of the task that consumes it, so a loop in a main-actor task can update UI directly.

```swift
@MainActor
func observeAuth() async {
  for await change in supabase.auth.events() {
    switch change.status {
    case .signedIn: showHome()
    case .signedOut: showSignIn()
    case .loading: break
    }
  }
}
```

### Cancel work

Auth honors task cancellation. The streams from ``AuthClient/events()`` finish when the consuming
task is cancelled, or when the client is released.

The client awaits the ``WebAuthPresenter`` that you give to
``AuthClient/signInWithOAuth(_:options:presenter:)``, so what a cancel does depends on the
presenter:

- ``ASWebAuthenticationSessionPresenter``, the default, closes the sign-in page and throws
  `CancellationError`. On tvOS the system cannot close the page, so the call throws while the page
  stays open until the user dismisses it. A new sign-in fails until then.
- ``ClosurePresenter`` only runs your closure. It cancels as far as the closure does.
- A presenter that you write must watch for cancellation itself.

### Write your own storage or presenter

A type that conforms to ``AuthStorage`` has `async` methods. Under
`NonisolatedNonsendingByDefault`, a method that you write in your own module runs on the caller's
actor too. If it does blocking work, such as a file read, mark it `@concurrent` so it moves off
the caller:

```swift
struct FileStorage: AuthStorage {
  @concurrent
  func load(key: String) async throws -> Data? {
    let url = url(for: key)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try Data(contentsOf: url)
  }

  // `save(_:key:)` and `remove(key:)` follow the same shape.
}
```

Return `nil` only when nothing is stored. Throw when the read fails, because the client treats `nil`
as "signed out".

A ``WebAuthPresenter`` is `@MainActor` by its protocol, so it can use UIKit and AppKit types
without more annotations. The closure that you give to ``ClosurePresenter`` is
`@MainActor @Sendable`. Capture the values that it needs, as in <doc:HandlingRedirectsAndDeepLinks>.
