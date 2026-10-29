// Journey: Realtime — broadcast between two clients, and Postgres changes for a row this run writes.
// Proof: the received payloads, saved as JSON, and the row's key in `key_value_storage`.
import Foundation
import Supabase

let sender = Verify.client()
let receiver = Verify.client()
let topic = Verify.unique("room")
let key = Verify.unique("kv")

Verify.step("rt-connect", "connect both clients")
_ = await Verify.attempt("rt-connect") {
  try await sender.realtime.connect()
  try await receiver.realtime.connect()
}

Verify.step("rt-broadcast", "receiver subscribes to \(topic); sender broadcasts 'ping'")
let inbox = await receiver.realtime.channel(topic)
let pings = await inbox.broadcasts(event: "ping")
let outbox = await sender.realtime.channel(topic)
_ = await Verify.attempt("rt-subscribe") {
  try await inbox.subscribe()
  try await outbox.subscribe()
}
Verify.check("rt-subscribe", await inbox.status.isSubscribed, "receiver status \(await inbox.status)")

_ = await Verify.attempt("rt-broadcast") {
  try await outbox.broadcast(event: "ping", payload: ["n": 1, "from": "sender"] as JSONObject)
}
if let message = await Verify.attempt("rt-broadcast", {
  try await Verify.within(seconds: 5) {
    var iterator = pings.makeAsyncIterator()
    return await iterator.next()
  }
}), let message {
  let payload: JSONObject? =
    if case .json(let json) = message.payload { json.objectValue } else { nil }
  Verify.save("rt-broadcast.json", payload ?? [:])
  Verify.check(
    "rt-broadcast", payload?["n"]?.intValue == 1 && payload?["from"]?.stringValue == "sender",
    "payload \(payload.map { "\($0)" } ?? "nil")")
}

Verify.step("rt-postgres-insert", "listen for INSERT on key_value_storage, then insert key \(key)")
let changes = await receiver.realtime.channel(Verify.unique("db"))
let inserts = await changes.postgresChanges(
  event: .insert, schema: "public", table: "key_value_storage")
let events = await changes.events()
_ = await Verify.attempt("rt-postgres-subscribe") { try await changes.subscribe() }
// The server confirms the Postgres listener after the subscribe reply. A write before that
// confirmation is never delivered. Stop on a failure too, so its reason is not lost to a timeout.
if let setup = await Verify.attempt("rt-postgres-subscribe", {
  try await Verify.within(seconds: 10) {
    await events.first { event in
      switch event {
      case .postgresChangesReady, .postgresChangesFailed: true
      default: false
      }
    }
  }
}), case .postgresChangesFailed(let reason) = setup {
  Verify.check("rt-postgres-subscribe", false, "server could not set up postgres changes: \(reason)")
}
_ = await Verify.attempt("rt-postgres-insert") {
  try await sender.from("key_value_storage")
    .insert(["key": key, "value": "from-verify"])
    .execute()
}
if let action = await Verify.attempt("rt-postgres-insert", {
  try await Verify.within(seconds: 10) {
    for await change in inserts where change.record?["key"]?.stringValue == key {
      return change.record?.values ?? [:]
    }
    return [:]
  }
}) {
  Verify.save("rt-postgres-insert.json", action)
  Verify.check(
    "rt-postgres-insert", action["key"]?.stringValue == key,
    "record \(action)")
}

await inbox.unsubscribe()
await outbox.unsubscribe()
await changes.unsubscribe()
print("KEY \(key)")
Verify.finish()
