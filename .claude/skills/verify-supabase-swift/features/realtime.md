# Realtime

An app opens a websocket with `client.realtime`, joins channels, sends and receives broadcast
messages, and listens to row changes in Postgres tables.

## Sub-features

- `rt-connect` connects the realtime socket for two separate clients.
- `rt-subscribe` joins a channel; its status becomes `subscribed`.
- `rt-broadcast` delivers a broadcast from one client to another on the same topic.
- `rt-postgres-insert` delivers an INSERT on `key_value_storage` to a channel that listens for it.

## How to get to it (user POV)

- `client.realtime.connect()`
- `client.realtime.channel(_:)`, then `channel.subscribe()` and `channel.unsubscribe()`
- `channel.broadcast(event:message:)` and `channel.broadcasts(event:)`
- `channel.postgresChanges(event: .insert, schema:table:)` and `channel.systemMessages()`

## Driving it with verify.sh

Preconditions:

- A run from `$V up` is live and `$V doctor` is all `ok`.
- `key_value_storage` is in the `supabase_realtime` publication (the integration migration
  adds it).

- **Connect and join.** Run `$V drive realtime`. Step `rt-subscribe` shows status `subscribed`.
- **Broadcast.** The sender broadcasts `ping` with `{"n": 1, "from": "sender"}`. Step
  `rt-broadcast` passes when the receiver gets it within 5 s, and saves `rt-broadcast.json`.
- **Postgres change.** The receiver listens for INSERT on `key_value_storage`, waits for the
  server's system message, then the sender inserts key `kv-<run-id>-<hex>` over PostgREST.
  Step `rt-postgres-insert` passes when the record arrives within 10 s, and saves
  `rt-postgres-insert.json`. The transcript prints `KEY <key>`.
- **Outside view.** Run
  `$V sql "select key, value from public.key_value_storage where key like 'kv-$VERIFY_RUN_ID-%'"`.
  The key from the transcript is present with value `from-verify`.

## Gotchas

- After `subscribe()` returns, the server still has to start the Postgres listener. It sends a
  system message when it is ready. A write before that message is never delivered. Wait for
  `systemMessages()` first, as the journey does.
- Register `postgresChanges(...)` and `broadcasts(event:)` before `subscribe()`, as the journey
  and the integration tests do. The join message carries the Postgres listener config.
- A client does not get its own broadcasts by default. Use two clients, or set
  `$0.broadcast.receiveOwnBroadcasts = true` in the channel config.
- Every wait needs a deadline (`Verify.within`). A missing event otherwise hangs the journey
  forever.
- Presence and private channels (RLS on `realtime.messages`) are not in the bundled journey.
