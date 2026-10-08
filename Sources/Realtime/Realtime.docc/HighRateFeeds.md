# High-Rate Feeds

Consume a busy channel without stalling the main actor or growing memory.

## Overview

Every data stream buffers without a limit. The client never drops an element and never ends a
stream because a consumer is slow: a bounded buffer would lose data without telling you. The
cost is on the consumer. If your loop falls behind, elements wait in memory until it catches up.
If a loop stops calling `next()` without ending, everything after that waits forever.

A loop that runs on the main actor does its work for each element on the main actor. At
hundreds of messages a second, that work competes with your UI. Do the per-element work
somewhere else, and send the main actor only what it shows.

### Aggregate off the main actor

Run the loop in a `@concurrent` function. Decode and fold each element there, and publish a
snapshot at the rate the screen can use:

```swift
nonisolated struct Tick: Decodable {
  let symbol: String
  let price: Double
}

@concurrent
func pump(_ ticks: RealtimeStream<BroadcastMessage>, into board: PriceBoard) async {
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

@MainActor @Observable
final class PriceBoard {
  var prices: [String: Double] = [:]
  func apply(_ snapshot: [String: Double]) { prices = snapshot }
}
```

Start it from the task that owns the channel:

```swift
.task {
  let channel = supabase.channel("prices")
  let ticks = channel.broadcasts(event: "tick")
  try? await channel.subscribe()
  await pump(ticks, into: board)
  await supabase.removeChannel(channel)
}
```

`Tick` is `nonisolated` because it decodes off the main actor. See <doc:TypedPayloads>.

This sketch publishes only when a new element arrives, so the last values of a burst wait for
the next message. Add a timer if the feed can go quiet.

### Status streams are different

``RealtimeClient/statusChanges`` and ``RealtimeChannel/statusChanges`` keep only the newest
value. A slow status consumer skips to the latest status and never builds up a backlog.
