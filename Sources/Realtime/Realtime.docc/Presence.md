# Presence

Show who is on a channel, across devices, without hitting the server's rate limit.

## Overview

Each client shares a payload with ``RealtimeChannel/track(_:encoder:)``. The server keeps the
set and sends it to every client on the channel. Read it with
``RealtimeChannel/presenceState``, ``RealtimeChannel/presenceStates()`` or
``RealtimeChannel/presenceChanges()``.

```swift
nonisolated struct Status: Codable {
  var name: String
  var typing: Bool
}

let key = userID.uuidString
let channel = await supabase.channel("room:42") { $0.presence.key = key }
let online = await channel.presenceStates()

try await channel.subscribe()
try await channel.track(Status(name: "Ana", typing: false))

for await state in online {
  let users = try state.decode(as: Status.self)
  show(users)
}
```

`Status` is `nonisolated` because the channel encodes it on its own executor. See
<doc:Isolation>.

### Turning presence on

The server sends presence only to a join that asks for it. A channel asks for it when a
presence stream is open at the time ``RealtimeChannel/subscribe()`` runs. So open
``RealtimeChannel/presenceStates()`` or ``RealtimeChannel/presenceChanges()`` before you
subscribe. Opened later, the stream reports an issue and finishes at once.

### Keys and devices

``RealtimeChannelConfiguration/Presence-swift.struct/key`` names this client's entry. Set it to
the user's id, so that one user is one key. When it is `nil`, the server picks a new key on
every join.

One key can hold many entries: one for each connection that tracks with it, such as a phone
and a laptop. ``PresenceState/entries`` maps each key to all its entries, and
``PresenceState/decode(as:decoder:ignoringUndecodable:)`` keeps that shape as `[String: [T]]`.
Count keys for "users online" and entries for "sessions online".

``RealtimeChannel/presenceChanges()`` yields only what joined and left in each sync. The first
sync after ``RealtimeChannel/subscribe()`` reports every present client as a join, and
``RealtimeChannel/unsubscribe()`` reports every client as a leave, so the changes always add up
to ``RealtimeChannel/presenceState``. An entry that tracks a new payload leaves with the old one
and joins with the new one.

### Rate limit

The server accepts five presence calls per channel in 30 seconds. The SDK does not combine or
delay calls: each ``RealtimeChannel/track(_:encoder:)`` and ``RealtimeChannel/untrack()`` goes
to the server as you make it. If your payload changes often, such as a "typing" flag, throttle
the calls in the app and send only the latest value.

### Rejoins

When the channel joins again, for example after a reconnect, the server has forgotten this
client's entry. The SDK does not track it again for you, as in supabase-js. Call
``RealtimeChannel/track(_:encoder:)`` again when ``RealtimeChannel/events()`` yields
``RealtimeChannelEvent/resubscribed``:

```swift
for await event in await channel.events() where event == .resubscribed {
  try? await channel.track(currentStatus)
}
```

After a rejoin, ``RealtimeChannel/presenceState`` keeps the last known clients until the server
sends the state for the new join.
