# Handling Errors

Tell a denied channel from a lost socket, and know which failures the client repairs on its own.

## Overview

Streams never throw. A call with one result does: ``RealtimeChannel/subscribe()``, a send, or a
decode. Every failure from such a call is a ``RealtimeError`` or a `CancellationError`. Check
``RealtimeError/kind`` first.

| Kind | When | What to do |
| --- | --- | --- |
| ``RealtimeError/Kind-swift.struct/unauthorized`` | The server rejected the token, or a policy denied the topic. | Fix the token or the policy. A retry does not help. |
| ``RealtimeError/Kind-swift.struct/timeout`` | A subscribe, a push or a REST broadcast did not complete in time. | Retry. |
| ``RealtimeError/Kind-swift.struct/notConnected`` | The socket went away while a reply was pending. | Retry when the status is connected again. |
| ``RealtimeError/Kind-swift.struct/notSubscribed`` | A send was attempted on a channel that is not subscribed. | Call ``RealtimeChannel/subscribe()`` first. |
| ``RealtimeError/Kind-swift.struct/rateLimited`` | The server applied a rate limit. | Slow down. The channel joins again after 30 seconds. |
| ``RealtimeError/Kind-swift.struct/channelRemoved`` | The channel was removed, or the server closed it. | Get a new channel from ``RealtimeClient/channel(_:configure:)``. |
| ``RealtimeError/Kind-swift.struct/transport`` | The network path failed. | Retry. ``RealtimeError/underlyingError`` is the `URLError` when there was one. |
| ``RealtimeError/Kind-swift.struct/server`` | The server answered with an error that has no narrower kind. | Read ``RealtimeError/code`` and ``RealtimeError/message``. |

``RealtimeError/Kind-swift.struct`` is an open set and has more members than this table. Keep a
fallback branch.

### Errors from subscribe

``RealtimeChannel/subscribe()`` throws when the server refuses the join or the join does not
complete. A `catch` clause can name a kind directly:

```swift
do {
  try await channel.subscribe()
} catch RealtimeError.Kind.unauthorized {
  signInAgain()
} catch RealtimeError.Kind.timeout {
  showRetry()
}
```

``RealtimeError/code`` is the code that the server put in front of its reason. It says which
check failed. ``RealtimeError/Code-swift.struct`` is an open set too: the server adds codes
without notice, so keep a fallback branch.

### Failures that are a status, not an error

A lost socket does not throw from a stream. It is a status on
``RealtimeClient/statusChanges()`` and ``RealtimeChannel/statusChanges()``. The client connects
again and joins its channels again on its own. See <doc:ConnectionBehavior>.

```swift
for await status in await channel.statusChanges() {
  if let error = status.error {
    log(error.message)
  }
}
```

A channel that the server closes does not join again. See
<doc:ConnectionBehavior#When-the-server-closes-a-channel>.

### Errors from the access token closure

``RealtimeClient/Configuration/accessToken`` supplies the token. When it throws during a join or
a heartbeat, the client keeps the current token. When it throws during
``RealtimeChannel/httpSend(event:payload:encoder:timeout:)``, the call throws a ``RealtimeError`` with kind
``RealtimeError/Kind-swift.struct/accessToken``, and your error is in
``RealtimeError/underlyingError``. No request is sent.

### Decoding

``BroadcastMessage/decode(as:decoder:)`` and the typed Postgres change methods throw a
``RealtimeError`` with kind ``RealtimeError/Kind-swift.struct/decoding`` when a payload does not
match your type. Decode inside the loop, so one bad message does not end the stream. See
<doc:TypedPayloads>.

### Cancellation

A cancelled task throws `CancellationError`, never a wrapped error. A cancelled task also ends a
`for await` loop over a stream without an error.
