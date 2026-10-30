// Journey: Realtime channel handles — presence, removeChannel then a new handle of the same topic,
// and unsubscribe then subscribe again on one handle.
// Proof: the presence names the stream and `presenceState` read, and the broadcasts a new or
// resubscribed handle receives.
import Foundation
import Supabase

let sender = Verify.client()
let receiver = Verify.client()

Verify.step("rt-connect", "connect both clients")
_ = await Verify.attempt("rt-connect") {
  try await sender.realtime.connect()
  try await receiver.realtime.connect()
}
Verify.check("rt-connect", await receiver.realtime.status.isConnected, "status \(await receiver.realtime.status)")

// Presence track and sync.
let presenceTopic = Verify.unique("presence")
Verify.step("rt-presence", "receiver watches presence on \(presenceTopic); sender tracks {name: sender}")
let watcher = await receiver.realtime.channel(presenceTopic)
let states = await watcher.presenceStates()
let tracker = await sender.realtime.channel(presenceTopic)
_ = await Verify.attempt("rt-presence-subscribe") {
  try await watcher.subscribe()
  try await tracker.subscribe()
}
_ = await Verify.attempt("rt-presence-track") {
  try await tracker.track(["name": "sender"] as JSONObject)
}
if let seen = await Verify.attempt("rt-presence", {
  try await Verify.within(seconds: 10) {
    for await state in states {
      let names = state.entries.values.flatMap { $0 }.compactMap { $0.payload["name"]?.stringValue }
      if names.contains("sender") { return names }
    }
    return []
  }
}) {
  Verify.save("rt-presence.json", seen)
  Verify.check("rt-presence", seen.contains("sender"), "stream saw \(seen)")
}
let readBack = await watcher.presenceState.entries.values.flatMap { $0 }
  .compactMap { $0.payload["name"]?.stringValue }
Verify.check("rt-presence-state", readBack.contains("sender"), "presenceState names \(readBack)")
_ = await Verify.attempt("rt-presence-untrack") { try await tracker.untrack() }
await watcher.unsubscribe()
await tracker.unsubscribe()

// removeChannel, then a new handle of the same topic subscribes at once.
let topic = Verify.unique("remove")
Verify.step("rt-remove-resubscribe", "subscribe a handle on \(topic), remove it, subscribe a new handle")
let first = await receiver.realtime.channel(topic)
_ = await Verify.attempt("rt-remove-first-subscribe") { try await first.subscribe() }
Verify.check("rt-remove-first-subscribe", await first.status.isSubscribed, "first status \(await first.status)")
await receiver.realtime.removeChannel(first)
Verify.check(
  "rt-remove-spent-status", "\(await first.status)" == "unsubscribed",
  "spent handle reads \(await first.status)")
let spentThrew = await {
  do {
    try await first.subscribe()
    return false
  } catch { return true }
}()
Verify.check("rt-remove-spent-subscribe-throws", spentThrew, "spent handle subscribe threw \(spentThrew)")
let second = await receiver.realtime.channel(topic)
Verify.check("rt-remove-new-handle", second != first, "new handle is a different channel")
let secondPings = await second.broadcasts(event: "pong")
_ = await Verify.attempt("rt-remove-second-subscribe") { try await second.subscribe() }
Verify.check("rt-remove-second-subscribe", await second.status.isSubscribed, "second status \(await second.status)")
let peer = await sender.realtime.channel(topic)
_ = await Verify.attempt("rt-remove-peer-subscribe") { try await peer.subscribe() }
_ = await Verify.attempt("rt-remove-broadcast") {
  try await peer.broadcast(event: "pong", payload: ["n": 2] as JSONObject)
}
if let got = await Verify.attempt("rt-remove-broadcast", {
  try await Verify.within(seconds: 5) {
    var iterator = secondPings.makeAsyncIterator()
    return await iterator.next()
  }
}) {
  Verify.check("rt-remove-broadcast", got != nil, "new handle received the broadcast")
}
let listed = await receiver.realtime.channels.map(\.topic)
Verify.check("rt-remove-channels", listed.filter { $0.hasSuffix(topic) }.count == 1, "channels \(listed)")

// unsubscribe then subscribe again on one handle.
Verify.step("rt-resubscribe", "unsubscribe then subscribe again on one handle")
await second.unsubscribe()
Verify.check("rt-unsubscribed", "\(await second.status)" == "unsubscribed", "status \(await second.status)")
let afterPings = await second.broadcasts(event: "pong")
_ = await Verify.attempt("rt-resubscribe") { try await second.subscribe() }
Verify.check("rt-resubscribe", await second.status.isSubscribed, "status \(await second.status)")
_ = await Verify.attempt("rt-resubscribe-broadcast") {
  try await peer.broadcast(event: "pong", payload: ["n": 3] as JSONObject)
}
if let got = await Verify.attempt("rt-resubscribe-broadcast", {
  try await Verify.within(seconds: 5) {
    for await message in afterPings {
      if case .json(let json) = message.payload, json.objectValue?["n"]?.intValue == 3 { return true }
    }
    return false
  }
}) {
  Verify.check("rt-resubscribe-broadcast", got, "handle received n=3 after resubscribe")
}
await second.unsubscribe()
await peer.unsubscribe()
Verify.finish()
