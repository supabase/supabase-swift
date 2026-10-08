# Presence

Show who is on a channel, across devices, without hitting the server's rate limit.

## Overview

Each client publishes a payload with ``RealtimePresence/track(_:encoder:)``. The server keeps
the set and sends it to every client on the channel. Read it with ``RealtimePresence/state``,
``RealtimePresence/states`` or ``RealtimePresence/changes``.

```swift
let channel = supabase.channel("room:42") {
  $0.presence.key = userID.uuidString
}
let online = channel.presence.states

try await channel.subscribe()
try await channel.presence.track(Status(name: "Ana", typing: false))

for await state in online {
  let users = try state.decode(as: Status.self)
  show(users)
}
```

### Keys and devices

``RealtimeChannelConfiguration/Presence/key`` names this client's entry. Set it to the user's id
so that one user is one key. When it is `nil`, the server picks a new key on every join.

One key can hold many entries: one per device or tab that tracks with it.
``PresenceState/entries`` maps each key to all its entries, and
``PresenceState/decode(as:decoder:ignoringUndecodable:)`` keeps that shape as `[String: [T]]`.
Count keys for "users online" and entries for "sessions online".

``RealtimePresence/changes`` yields only what joined and left in each update. An entry that
tracks a new payload leaves with the old one and joins with the new one.

### Rate limit and coalescing

The server accepts five presence calls per channel in 30 seconds. The SDK keeps under that
limit: it sends at most one ``RealtimePresence/track(_:encoder:)`` or
``RealtimePresence/untrack()`` call per channel every six seconds.

A call inside that window does not wait for the server. It queues its payload and returns. The
newest queued payload goes out when the window ends, and a payload equal to the last one sent is
not sent again. So a coalesced call that returns without an error only tells you the payload is
queued. Call ``RealtimePresence/track(_:encoder:)`` as often as the state changes; the SDK sends
the latest.

### Rejoins

After a rejoin the server has forgotten this client's entry. The SDK tracks the last payload
again on its own, until you call ``RealtimePresence/untrack()``. ``RealtimePresence/state`` is
empty until the server sends the set for the new join.

### Enabling presence on a channel

The server sends presence only to a join that asks for it. Presence turns on when you call
``RealtimePresence/track(_:encoder:)``, or when you make the first ``RealtimePresence/states``
or ``RealtimePresence/changes`` stream on a channel. On a channel that is already joined, that
makes the channel join again, with a ``RealtimeChannelEvent/resubscribed`` event. Make the
presence stream before ``RealtimeChannel/subscribe()`` to join once.
