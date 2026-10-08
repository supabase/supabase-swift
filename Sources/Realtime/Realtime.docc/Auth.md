# Authorization

Give the client a token, keep it fresh, and protect private channels with row level security.

## Overview

Every join carries an access token. The server checks it on join and closes the channel when it
expires. The client gets tokens from a provider closure, or from ``RealtimeClient/setAuth(_:)``.

### The provider closure

``RealtimeClientOptions/accessToken`` returns the token to join with:

```swift
var options = RealtimeClientOptions()
options.headers[HTTPField.Name("apikey")!] = publishableKey
options.accessToken = { try await session.currentAccessToken() }

let realtime = RealtimeClient(
  url: URL(string: "https://<ref>.supabase.co/realtime/v1")!,
  options: options
)
```

The client calls it before each connect. When the token is a JWT, the client also calls it
60 seconds before the token's `exp` and sends the new token to every joined channel, so a
channel never reaches the server's expiry check.

`SupabaseClient` sets this closure for you. It returns the Auth session's token, or the
publishable key when nobody is signed in, and it sends the new token after every sign-in,
refresh and sign-out. Do not set `accessToken` in `SupabaseClientOptions.realtime`; the client
reports an issue when you do.

### When a token expires

If a token expires anyway, for example because the provider failed or the device slept through
the refresh, the server closes the channel. The client asks the provider for a new token and
joins again; the channel goes through
``RealtimeChannelStatus/resubscribing(attempt:retryIn:lastError:)`` and yields
``RealtimeChannelEvent/resubscribed``.

If that join also fails with an expired token, the channel stops in
``RealtimeChannelStatus/failed(_:)``. Without a provider the client has nothing new to send, so
call ``RealtimeClient/setAuth(_:)`` before the old token expires.

### Private channels and row level security

A private channel checks the caller's token against the row level security policies on
`realtime.messages`, on join and on every broadcast and presence call.

```swift
let channel = supabase.channel("room:42") { $0.isPrivate = true }
do {
  try await channel.subscribe()
} catch let error as RealtimeError where error.kind == .unauthorized {
  // The policy denied this user, or nobody is signed in.
}
```

A denied join is final. ``RealtimeChannel/subscribe()`` throws a
``RealtimeError/Kind-swift.struct/unauthorized`` error whose ``RealtimeError/isRetryable`` is
`false`, and the channel stays in ``RealtimeChannelStatus/failed(_:)``. The client does not
retry. This is what happens with the publishable (anon) key on a private channel: sign the user
in, then subscribe again.

With ``RealtimeChannelConfiguration/Broadcast/acknowledge`` on, a broadcast that a policy denies
fails with ``RealtimeError/Kind-swift.struct/timeout``, because the server does not reply to it.

### Third-party auth

With `SupabaseClient`, set `SupabaseClientOptions.AuthOptions.accessToken`. Realtime uses the
same closure as every other module.

With a standalone ``RealtimeClient``, set ``RealtimeClientOptions/accessToken`` to your auth
library's token getter. When your library tells you the token changed, call
``RealtimeClient/setAuth(_:)``:

```swift
await realtime.setAuth(newToken)   // send this token now
await realtime.setAuth(nil)        // ask the provider again
```

A token from ``RealtimeClient/setAuth(_:)`` stays until the next call or the provider's next
result. Without a provider, `setAuth(nil)` keeps the current token.
