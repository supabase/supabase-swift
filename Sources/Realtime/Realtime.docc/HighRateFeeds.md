# High-Rate Feeds

Read a busy channel without stalling the main actor.

## Overview

Every stream buffers without a limit. The client never drops an element and never ends a stream
because a consumer is slow: a bounded buffer would lose data without telling you. The cost is on
the consumer. If your loop falls behind, elements wait in memory until it catches up. If a loop
stops calling `next()` without ending, every later element waits in memory until the stream
ends.

A loop that runs on the main actor does its work for each element on the main actor. At
hundreds of messages a second, that work competes with your UI. Do the work for each element
somewhere else, and send the main actor only what it shows.

### Aggregate off the main actor

Run the loop in a `@concurrent` function. Decode and fold each element there, and publish a
snapshot at the rate the screen can use:

```swift
nonisolated struct Tick: Decodable {
  let symbol: String
  let price: Double
}

@MainActor @Observable
final class PriceBoard {
  var prices: [String: Double] = [:]
  func apply(_ snapshot: [String: Double]) { prices = snapshot }
}

@concurrent
func pump(_ ticks: AsyncStream<BroadcastMessage>, into board: PriceBoard) async {
  var latest: [String: Double] = [:]
  var lastPublish = ContinuousClock.now
  for await message in ticks {
    guard let tick = try? message.decode(as: Tick.self) else { continue }
    latest[tick.symbol] = tick.price
    if ContinuousClock.now - lastPublish >= .milliseconds(100) {
      await board.apply(latest)
      lastPublish = .now
    }
  }
}
```

Start it from the task that owns the channel:

```swift
.task {
  let channel = await supabase.channel("prices")
  let ticks = await channel.broadcasts(event: "tick")
  try? await channel.subscribe()
  await pump(ticks, into: board)
  await supabase.removeChannel(channel)
}
```

`Tick` is `nonisolated` because it decodes off the main actor. See <doc:Isolation>.

This sketch publishes only when a new element arrives, so the last values of a burst wait for
the next message. Add a timer if the feed can go quiet.

### Status streams

``RealtimeClient/statusChanges()`` and ``RealtimeChannel/statusChanges()`` also buffer every
value. They change only when the connection or the join changes, so reading them on the main
actor is fine. To get only the latest status, read ``RealtimeClient/status`` or
``RealtimeChannel/status`` when you need it.
