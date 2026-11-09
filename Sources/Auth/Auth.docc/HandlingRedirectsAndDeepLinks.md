# Handling redirects and deep links

Finish a sign-in that leaves your app for a browser or an email, and route each URL once.

## Overview

Some flows send the user away and return with a URL: OAuth and single sign-on, a magic link, an
email confirmation, a password reset, an email change, and an identity link. Auth finishes each
one from the URL. Two paths bring the URL back:

- The browser flow, ``AuthClient/signInWithOAuth(_:options:presenter:)``. A ``WebAuthPresenter``
  opens the provider page and returns the callback URL, and the client finishes the flow. You
  write no URL handling.
- The links that open your app, such as an email link. You pass the URL to
  ``AuthClient/handleRedirect(_:)``.

### Set the redirect URL

Give the client the URL that the server sends the user to, and register it with the system. The
URL must also be on the redirect allow list of your Supabase project.

```swift
let supabase = try SupabaseClient(
  supabaseURL: URL(string: "https://xyzcompany.supabase.co")!,
  supabaseKey: "your-publishable-key",
  configuration: .init(auth: .init(redirectTo: URL(string: "com.example.app://callback")!))
)
```

A custom scheme, such as `com.example.app`, needs a URL type in the `Info.plist` of the app. A
universal link needs the associated domain, as the section on universal links below says.

### Handle the URL from onOpenURL

Pass the URL to the client from `onOpenURL`, on the root view of the scene. The client reads the
URL and finds the flow. It returns `nil` for a URL that is not an auth redirect.

A URL is an auth redirect only when it opens a known callback: the redirect URL of the client, or
the `redirectTo` of a flow that waits for its result. The scheme, host, port, and path must match.
A trailing slash is ignored. So `com.example.app://invite?code=ABC` is not an auth redirect when
the callback is `com.example.app://callback`. When no callback is known, no URL is an auth
redirect.

```swift
@main
struct MyApp: App {
  var body: some Scene {
    WindowGroup {
      RootView()
        .onOpenURL { url in
          Task {
            do {
              switch try await supabase.auth.handleRedirect(url) {
              case .signedIn(_, verification: .recovery):
                showPasswordReset()
              case .signedIn, .emailChangePending, nil:
                break
              }
            } catch {
              showError(error)
            }
          }
        }
    }
  }
}
```

The session lands in storage and the client emits one auth event. A view that follows
<doc:ObservingAuthStateInSwiftUI> updates with no more code.

Pass only URLs that reach your own callback. A URL with tokens (`#access_token=…`) signs in the
account that the tokens belong to, and anyone who can make your app open a URL can send one.

### Route auth URLs apart from other links

When the app also opens other deep links, ask the client first with
``AuthClient/isAuthRedirect(_:)``. It applies the same rule as
``AuthClient/handleRedirect(_:)``. It reads the pending flows from storage, so it is `async`, but
it sends no request.

```swift
.onOpenURL { url in
  Task {
    if await supabase.auth.isAuthRedirect(url) {
      try await supabase.auth.handleRedirect(url)
    } else {
      router.open(url)
    }
  }
}
```

### Present the provider page with SwiftUI

On Apple platforms, the default presenter is ``ASWebAuthenticationSessionPresenter``. To use the
`webAuthenticationSession` value from the SwiftUI environment instead, wrap it in a
``ClosurePresenter``. The environment value is available on iOS 16.4 and later.

Import both `AuthenticationServices` and `SwiftUI`. The environment value comes from the overlay
of the two frameworks.

```swift
import AuthenticationServices
import Supabase
import SwiftUI

@available(iOS 16.4, macOS 13.3, tvOS 16.4, *)
struct SignInView: View {
  @Environment(\.webAuthenticationSession) private var webAuthenticationSession

  var body: some View {
    Button("Sign in with GitHub") {
      Task {
        do {
          try await supabase.auth.signInWithOAuth(
            .github,
            options: OAuthOptions(redirectTo: URL(string: "com.example.app://callback")),
            presenter: ClosurePresenter { [webAuthenticationSession] url, callbackScheme in
              try await webAuthenticationSession.authenticate(
                using: url,
                callbackURLScheme: callbackScheme ?? "com.example.app"
              )
            }
          )
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
          // The user closed the page. This is a cancel, not a failure.
        } catch {
          showError(error)
        }
      }
    }
  }
}
```

``ClosurePresenter`` passes on the error of its closure. When the user closes the page, SwiftUI's
`webAuthenticationSession` throws `ASWebAuthenticationSessionError` with the code `.canceledLogin`,
so catch that error. The default ``ASWebAuthenticationSessionPresenter`` turns it into
`CancellationError` for you.

### Use a universal link

An HTTPS redirect URL, such as `https://example.com/auth/callback`, is a universal link. Add the
`webcredentials:example.com` associated domain to the app, and host the matching
`apple-app-site-association` file on that domain.

The default ``ASWebAuthenticationSessionPresenter`` listens for the HTTPS callback on iOS 17.4,
macOS 14.4, tvOS 17.4, visionOS 1.1, and watchOS 10.4 and later. Use it for a universal link,
because it knows the full redirect URL. A ``ClosurePresenter`` gets only the scheme, which is
`https`, so it cannot tell your link from any other. To use the SwiftUI environment value with a
universal link, write a presenter that adopts ``WebAuthPresenter/authenticate(url:redirectURL:)``
and passes `.https(host:path:)` to `authenticate(using:callback:additionalHeaderFields:)`.

```swift
@available(iOS 17.4, macOS 14.4, tvOS 17.4, visionOS 1.1, watchOS 10.4, *)
struct UniversalLinkPresenter: WebAuthPresenter {
  let session: WebAuthenticationSession

  @MainActor
  func authenticate(url: URL, callbackScheme: String?) async throws -> URL {
    try await authenticate(url: url, redirectURL: nil)
  }

  @MainActor
  func authenticate(url: URL, redirectURL: URL?) async throws -> URL {
    try await session.authenticate(
      using: url,
      callback: .https(host: "example.com", path: "/auth/callback"),
      additionalHeaderFields: [:]
    )
  }
}
```

### Route each URL once

The same URL can reach your app more than once, for example from both a scene delegate and
`onOpenURL`. The client protects the exchange. A code works once, so a second exchange would fail
and hide the first. The client therefore remembers its recent redirects. A second call with the
same URL returns the same result, or throws the same error, and sends no request.

That protects the session, not your own code. A second delivery still runs your handler a second
time, which can show the password reset screen twice. Follow these rules:

- Handle auth redirects in one place. Use `onOpenURL` or a scene delegate, not both.
- Do not pass the callback URL of a browser flow to ``AuthClient/handleRedirect(_:)``. The
  presenter returns it to ``AuthClient/signInWithOAuth(_:options:presenter:)``, which finishes the
  flow.
- Do not pass the code of a URL to ``AuthClient/exchangeCodeForSession(_:flowID:)`` when you also
  pass the URL to ``AuthClient/handleRedirect(_:)``. The method does not deduplicate.

A transport error is replayed too, so a second ``AuthClient/handleRedirect(_:)`` of the same URL
throws the same error. To retry after the network comes back, call
``AuthClient/exchangeCodeForSession(_:flowID:)`` with the code. The client keeps the flow after a
transport error, so the retry can succeed.
