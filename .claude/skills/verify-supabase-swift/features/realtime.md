# Realtime

An app opens a websocket with `client.realtime`, joins channels, sends and receives broadcast
messages, and listens to row changes in Postgres tables.

## Sub-features

- `rt-connect` connects the realtime socket for two separate clients.
- `rt-subscribe` joins a channel; its status becomes `subscribed`.
- `rt-broadcast` delivers a broadcast from one client to another on the same topic.
- `rt-postgres-insert` delivers an INSERT on `key_value_storage` to a channel that listens for it.
- `rt-presence` delivers a tracked presence entry to a watcher, in `presenceStates()` and in
  `await presenceState`.
- `rt-remove-resubscribe` removes a channel; the handle is spent, and a new handle of the same
  topic subscribes at once and receives broadcasts.
- `rt-resubscribe` unsubscribes and subscribes again on one handle, which receives broadcasts again.

## How to get to it (user POV)

- `client.realtime.connect()` and `await client.realtime.status`
- `await client.realtime.channel(_:)`, then `channel.subscribe()` and `channel.unsubscribe()`
- `channel.broadcast(event:payload:)` and `await channel.broadcasts(event:)`
- `await channel.postgresChanges(event: .insert, schema:table:)` and `await channel.events()`
- `channel.track(_:)`, `await channel.presenceStates()` and `await channel.presenceState`
- `await client.realtime.removeChannel(_:)`, `await client.realtime.channels` and
  `await channel.status`

## Driving it with verify.sh

Preconditions:

- A run from `$V up` is live and `$V doctor` is all `ok`.
- `key_value_storage` is in the `supabase_realtime` publication (the integration migration
  adds it).

- **Connect and join.** Run `$V drive realtime`. Step `rt-subscribe` shows status `subscribed`.
- **Broadcast.** The sender broadcasts `ping` with `{"n": 1, "from": "sender"}`. Step
  `rt-broadcast` passes when the receiver gets it within 5 s, and saves `rt-broadcast.json`.
- **Postgres change.** The receiver listens for INSERT on `key_value_storage`, waits for
  `.postgresChangesReady` from `events()`, then the sender inserts key `kv-<run-id>-<hex>` over PostgREST.
  Step `rt-postgres-insert` passes when the record arrives within 10 s, and saves
  `rt-postgres-insert.json`. The transcript prints `KEY <key>`.
- **Outside view.** Run
  `$V sql "select key, value from public.key_value_storage where key like 'kv-$VERIFY_RUN_ID-%'"`.
  The key from the transcript is present with value `from-verify`.
- **Presence.** Run `$V drive realtime-actor`. The watcher opens `presenceStates()`, then both
  clients subscribe, and the sender tracks `{"name": "sender"}`. Step `rt-presence` passes when
  the stream shows `sender` within 10 s, and saves `rt-presence.json`. `rt-presence-state`
  passes when `await presenceState` shows it too.
- **Remove, then a new handle.** Step `rt-remove-resubscribe` subscribes a handle, calls
  `removeChannel`, and checks that the spent handle reads `unsubscribed` and that `subscribe()`
  on it throws. A new handle of the same topic subscribes at once, receives a broadcast from a
  peer within 5 s, and `await channels` lists the topic once.
- **Resubscribe.** Step `rt-resubscribe` unsubscribes the handle, opens a new stream, subscribes
  again, and passes when the handle receives a broadcast within 5 s.

## Gotchas

- After `subscribe()` returns, the server still has to start the Postgres listener. It reports
  `.postgresChangesReady` on `events()` when it is ready. A write before that is never
  delivered. Wait for it first, as the journey does.
- Register `postgresChanges(...)` and `broadcasts(event:)` before `subscribe()`, as the journey
  and the integration tests do. The join message carries the Postgres listener config.
- A client does not get its own broadcasts by default. Use two clients, or set
  `$0.broadcast.receiveOwnMessages = true` in the channel config.
- Every wait needs a deadline (`Verify.within`). A missing event otherwise hangs the journey
  forever.
- `channel(_:)`, every stream method, and `status` are `async`: write `await` at each call. A
  stream is registered when its call returns, so open it before the action that causes events.
- Private channels (RLS on `realtime.messages`) are not in a bundled journey.
- Open `presenceStates()` before `subscribe()`. The join request carries the presence config.
- `removeChannel` spends the handle. Take a new handle with `channel(_:)` to subscribe the topic
  again. `unsubscribe()` keeps the handle, so `subscribe()` joins again on it.
