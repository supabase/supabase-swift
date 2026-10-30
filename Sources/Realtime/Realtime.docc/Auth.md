# Authorization

Give the client a token, keep it fresh, and protect private channels with row level security.

## Overview

Every join carries an access token. The server checks it on join and closes the channel when it
expires. The client gets tokens from a closure, ``RealtimeClientOptions/accessToken``, or from
``RealtimeClient/setAuth(_:)``.

### The token closure

``RealtimeClientOptions/accessToken`` returns the token to join with:

```swift
let options = RealtimeClientOptions(
  headers: ["apikey": publishableKey],
  accessToken: { try await session.currentAccessToken() }
)
let realtime = RealtimeClient(
  url: URL(string: "https://<project-ref>.supabase.co/realtime/v1")!,
  options: options
)
```

The client calls the closure before a join and when a heartbeat goes out, at most once every 10
seconds. A call that throws, returns `nil`, or does not return within
``RealtimeClientOptions/requestTimeout`` keeps the current token.

When the token is a JWT, the client also calls the closure 60 seconds before the token's `exp`,
while it is connected, and sends the new token to every joined channel. So a channel does not
reach the server's expiry check.

`SupabaseClient` sets this closure for you. It returns the signed-in user's token. After every
sign-in, token refresh and sign-out, `SupabaseClient` also sends the new token with
``RealtimeClient/setAuth(_:)``; after a sign-out, that is the project key. Do not set
`accessToken` in `SupabaseClientOptions.realtime`: the client reports an issue when you do.

### When a token expires

A token can expire anyway, for example because the closure failed or the device slept through
the refresh. What happens next depends on the channel's state:

- **A join that the server refuses for an expired token.** The client calls the closure again at
  once and joins one more time with the new token. If that join also fails with an expired
  token, the channel stops in ``RealtimeChannelStatus/failed(_:)``, and
  ``RealtimeChannel/subscribe()`` throws.
- **A joined channel.** The server closes it. The client does not join it again: the channel
  becomes ``RealtimeChannelStatus/unsubscribed`` and its streams end. Make sure a valid token is
  available, then ask the client for a new channel and subscribe it. See
  <doc:ConnectionBehavior#When-the-server-closes-a-channel>.

Without a closure, the client has nothing new to send, so call ``RealtimeClient/setAuth(_:)``
before the old token expires.

### Private channels and row level security

A private channel checks the caller's token against the row level security policies on
`realtime.messages`. See the
[Realtime authorization guide](https://supabase.com/docs/guides/realtime/authorization).

```swift
let channel = await supabase.channel("room:42") { $0.isPrivate = true }
do {
  try await channel.subscribe()
} catch let error as RealtimeError where error.kind == .unauthorized {
  // A policy denied this user, or nobody is signed in.
}
```

A denied join is final. ``RealtimeChannel/subscribe()`` throws a ``RealtimeError`` of kind
``RealtimeError/Kind-swift.struct/unauthorized`` whose ``RealtimeError/isRetryable`` is `false`,
and the channel stays in ``RealtimeChannelStatus/failed(_:)``. The client does not retry. This is
what happens with the publishable key on a private channel: sign the user in, then subscribe
again.

The server works out the channel's permissions when the channel joins, from the policies, the
token and the topic, and checks each broadcast and presence call against them. To make sure a
changed policy applies, remove the channel and join again.

With ``RealtimeChannelConfiguration/Broadcast-swift.struct/acknowledge`` on, a broadcast that a
policy denies fails with ``RealtimeError/Kind-swift.struct/timeout``, because the server does not
reply to it.

### Third-party auth

With `SupabaseClient`, set the `accessToken` closure in `SupabaseClientOptions.AuthOptions`.
Realtime uses the same closure as every other module.

With a standalone ``RealtimeClient``, set ``RealtimeClientOptions/accessToken`` to your auth
library's token getter. When your library tells you the token changed, call
``RealtimeClient/setAuth(_:)``:

```swift
await realtime.setAuth(newToken)  // Send this token now.
await realtime.setAuth()          // Ask the closure again.
```

A token from ``RealtimeClient/setAuth(_:)`` stays until the next call or the closure's next
result. Without a closure, `setAuth()` keeps the current token.
