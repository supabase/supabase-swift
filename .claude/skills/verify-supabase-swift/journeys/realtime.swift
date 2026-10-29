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
let inbox = receiver.realtime.channel(topic)
let pings = inbox.broadcastStream(event: "ping")
let outbox = sender.realtime.channel(topic)
_ = await Verify.attempt("rt-subscribe") {
  try await inbox.subscribeWithError()
  try await outbox.subscribeWithError()
}
Verify.check("rt-subscribe", inbox.status == .subscribed, "receiver status \(inbox.status.rawValue)")

_ = await Verify.attempt("rt-broadcast") {
  try await outbox.broadcast(event: "ping", message: ["n": 1, "from": "sender"] as JSONObject)
}
if let message = await Verify.attempt("rt-broadcast", {
  try await Verify.within(seconds: 5) {
    var iterator = pings.makeAsyncIterator()
    return await iterator.next()
  }
}), let message {
  Verify.save("rt-broadcast.json", message)
  let payload = message["payload"]?.objectValue
  Verify.check(
    "rt-broadcast", payload?["n"]?.intValue == 1 && payload?["from"]?.stringValue == "sender",
    "payload \(payload.map { "\($0)" } ?? "nil")")
}

Verify.step("rt-postgres-insert", "listen for INSERT on key_value_storage, then insert key \(key)")
let changes = receiver.realtime.channel(Verify.unique("db"))
let inserts = changes.postgresChange(
  InsertAction.self, schema: "public", table: "key_value_storage")
let system = changes.system()
_ = await Verify.attempt("rt-postgres-subscribe") { try await changes.subscribeWithError() }
// The server confirms the Postgres listener with a system message after the subscribe reply.
// A write before that message is never delivered.
_ = await Verify.attempt("rt-postgres-subscribe") {
  try await Verify.within(seconds: 10) {
    var iterator = system.makeAsyncIterator()
    _ = await iterator.next()
  }
}
_ = await Verify.attempt("rt-postgres-insert") {
  try await sender.from("key_value_storage")
    .insert(["key": key, "value": "from-verify"])
    .execute()
}
if let action = await Verify.attempt("rt-postgres-insert", {
  try await Verify.within(seconds: 10) {
    for await action in inserts where action.record["key"]?.stringValue == key {
      return action.record
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
