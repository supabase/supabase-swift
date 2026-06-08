# Realtime v3 — Questions for the Realtime Backend Team

Each section pairs **an assumption baked into the v3 Swift design** with
**the question(s) that need to be validated**. If an assumption is wrong, the
linked §§ in `realtime-v3.md` need revisiting.

---

## 1. Connection / Socket

**Assumption A1.** WebSocket auth is a single `apikey` query param / header.
No additional handshake. (§1.1, §6.1)

- Is `apikey` the only required auth on connect, or should we also send
  `Authorization: Bearer <jwt>` and/or `vsn` as a query param?
- Are there any required subprotocols (`Sec-WebSocket-Protocol`) we should
  be setting?

**Assumption A2.** `vsn=2.0.0` is the preferred wire version and is stable.
(§1.2, §11, Config.protocolVersion)

- Is v2 (binary broadcast frames + array-encoded messages) the recommended
  default for new clients?
- Any plans for v3? If so, what's the rough shape, and should we design an
  escape hatch for it?
- Are there server deployments still pinned to v1 where v2 would break?

**Assumption A3.** Default heartbeat interval 25s is safe. (§1.2, §6.4)

- What's the server-side heartbeat timeout (after how many missed
  heartbeats does the server close the socket)?
- Are there Cloudflare/LB-level idle timeouts that could close an
  otherwise-healthy socket? If so, what's the max safe heartbeat interval?

**Assumption A4.** Heartbeat RTT is exposed as `phx_reply` latency and is
the canonical "is the connection healthy" signal. (§6.4, `ConnectionStatus.latency`)

- Is `phx_reply` the right signal, or does the server also push periodic
  presence/state messages we could use?
- Is there any server-initiated "ping" the client is expected to respond to?

---

## 2. Channel Join / Leave

**Assumption B1.** A client may have at most one live subscription per
topic per socket. A second `phx_join` on the same topic while one is live
is rejected or ignored. (§2.1, §2.3)

- Confirmed? If a second `phx_join` is sent for an already-joined topic,
  what does the server do — error, overwrite, or dedupe silently?
- Does the server enforce a max number of topics per socket? What's the limit?

**Assumption B2.** `phx_leave` is always ACKed by the server before the
server-side state is torn down. (§2.3 "await-to-ack")

- Is `phx_leave` always ACKed? Under what conditions can it not be
  (e.g., server shutdown mid-leave)?
- After ACK, is it safe to assume no further events for that topic will
  arrive on this socket?
- If the socket drops mid-leave, what's the server's cleanup behavior?
  (We need to know whether a reconnecting client should re-send leave
  or just skip it.)

**Assumption B3.** A `phx_join` immediately after `phx_leave` on the same
topic is valid and produces a fresh subscription. (§2.3 "pipelined re-acquire")

- If the client sends `phx_leave` then `phx_join` back-to-back (before
  leave is ACKed), does the server queue them in order, reject the join,
  or race them?
- Is there a minimum cooldown between leave and rejoin on the same topic?

**Assumption B4.** Dropping a client socket without leaving joined
channels is safe — the server GCs subscriptions within some finite window.
(§2.1 "leaked-channel warning")

- What's the server-side cleanup delay for abandoned subscriptions?
- Are there billing/quota implications for abandoning vs leaving?
  (We want to know how loud our leak warning should be.)

---

## 3. Channel Join Config

**Assumption C1.** The entire `config` object is frozen at `phx_join` time.
No way to mutate `broadcast.ack`, `self`, `replay`, `presence.key`, or
`postgres_changes` mid-subscription without leaving and rejoining.
(§2.2 "options are locked at creation")

- Confirmed? Are any of these fields mutable mid-flight?
- If a caller needs to change `postgres_changes` filters, is the correct
  pattern always leave + rejoin, or is there a `phx_update`-style event?

**Assumption C2.** `private: true` channels go through RLS at join time
and reject if the JWT is invalid or lacks permission. (§2.2)

- What's the exact error the server returns on unauthorized private-channel
  join? (`reason` string format, so we can map to `.authenticationFailed`
  vs `.channelJoinRejected`.)
- Does `private: true` have implications for broadcast and postgres_changes
  behavior beyond the join check?

---

## 4. Broadcast — WebSocket

**Assumption D1.** `broadcast.ack: true` means every broadcast send gets a
`phx_reply` from the server. `ack: false` means none. (§3.2, BroadcastOptions.acknowledge)

- Confirmed? What's the exact correlation mechanism — by `ref`?
- What's a reasonable default `broadcastAckTimeout`? (We picked 5s.)

**Assumption D2.** `self: true` echoes broadcasts back to the sender.
`self: false` does not. This is channel-wide, not per-message. (§3.2, Decision 23)

- Confirmed channel-wide only, no per-message override?
- Ordering guarantee: if I broadcast 3 messages with `self: true`, are the
  echoes guaranteed to arrive in send order?

**Assumption D3.** v2 protocol sends broadcast payloads as binary frames
(opcode 0x02), type byte `0x03` (client→server) / `0x04` (server→client).
Non-broadcast messages are text frames with JSON arrays. (§3.1, memory: protocol 2.0.0)

- Confirmed? What's the exact binary framing — is the payload length
  length-prefixed, or end-of-frame delimited?
- Is there a max binary frame size the server enforces?

**Assumption D4.** Arbitrary `Data` can be broadcast as a binary payload
without JSON encoding. (§3.2, Decision 25)

- Does the server inspect broadcast payloads, or is any byte string valid?
- Any size limits specific to binary vs JSON broadcasts?

**Assumption D5.** Broadcast delivery is best-effort — no retry, no queue,
no ordering guarantees across topics. Within a single topic + sender,
order is preserved. (§3.1 "streams pause silently during reconnection")

- Within-topic, within-sender order: guaranteed? (We document it as such.)
- Any cross-topic ordering guarantees we should not assume away?
- Are there rate limits? If so, what does the server return when exceeded?

---

## 5. Broadcast — HTTP Endpoint

**Assumption E1.** `POST /realtime/v1/api/broadcast` is the correct endpoint
for one-shot broadcasts without opening a WS. (§3.3 httpBroadcast)

- Is that the canonical path? Is there a versioned alternative?
- Request body shape — batch-only (`{ messages: [...] }`) or single also
  accepted?
- Response shape on success (200? 204? body?)
- Error shape — structured JSON with `code`/`message`?

**Assumption E2.** HTTP broadcast uses the same `apikey` and JWT auth as
the WebSocket. (§3.3 "Auth uses the same `APIKeySource`")

- Confirmed? Header names: `apikey`, `Authorization: Bearer <jwt>`?
- Does HTTP broadcast honor RLS for private topics? If the JWT lacks
  permission, what's the error?

**Assumption E3.** HTTP broadcast emits the message to all WS subscribers
on that topic exactly as if a WS client had sent it. (§3.3)

- Confirmed? Does `self: true` (if the sender happens to also have a WS
  subscription to the topic) apply to HTTP-originated broadcasts?

**Assumption E4.** HTTP broadcast has its own rate limits distinct from WS.

- What are they? How are they communicated — `429` with `Retry-After`
  header? Any per-topic limits vs per-project?

---

## 6. Broadcast Replay

**Assumption F1.** `replay.since: unix_ms` + optional `limit` is set in the
join config, and the server replays matching messages at join time before
live events start flowing. (§2.2 BroadcastOptions.replay)

- Confirmed join-time-only? Can replay be re-triggered mid-subscription?
- What's the server-side retention window? If `since` is older than
  retention, does the server return the partial window + newest first,
  or return an error?
- Default `limit` if omitted? Max `limit` the server enforces?
- Does replay interact with `self: false`? (E.g., will it replay my own
  messages even if self-echo is off?)
- Does replay cover private channels the same way as public?
- Ordering: are replayed messages guaranteed to arrive before any live
  events after join?

---

## 7. Presence

**Assumption G1.** Phoenix presence allows multiple `track` calls from the
same socket under the same presence key, each registering a distinct meta
entry. (§4 multi-track support, Decision 16)

- Confirmed? Or does `track` overwrite any prior meta for the same key?
- If multi-meta: is there a server-enforced max metas per key?

**Assumption G2.** `presence.key` in join config sets this client's
presence key. If nil, the server generates one (random/per-connection).
(§4 "Presence key source", Decision 17, 45)

- Confirmed the server generates if nil? What's the format
  (UUID, random string)?
- Is the generated key stable across reconnects of the same socket, or
  fresh every connect?

**Assumption G3.** There's an explicit "untrack" mechanism (the
`presence.untrack` event, or similar). Dropping all metas requires an
explicit untrack — merely going silent does not remove presence.
(§4 PresenceHandle.cancel)

- Confirmed? What's the wire-level untrack event?
- Is untrack ACKed? (We document await-to-ack.)
- If I have 3 tracks and want to untrack one, how does the server know
  which meta to remove — meta content match, or a per-track ref?

**Assumption G4.** On `phx_leave`, the server removes all presence metas
for that socket+topic without requiring explicit untracks. (§4
"when `channel.leave()` is called, all outstanding tracks are implicitly
torn down server-side")

- Confirmed? Or must we send explicit untracks before leave?

**Assumption G5.** Presence is **not** auto-restored by the server on
rejoin. The client must re-send `track` for each live state after the
rejoin `phx_reply`. (§4 "auto re-track on reconnect", §9.2, Decision 18)

- Confirmed the server does NOT remember presence across reconnects?
- If the server does remember: we need to either skip re-tracking
  (optimal) or detect and reconcile (harder).

**Assumption G6.** `presence_state` (snapshot) arrives once per join;
`presence_diff` arrives for every subsequent change. (§4 `observe` vs `diffs`)

- Confirmed? Does the snapshot always arrive even when joining an empty
  presence set?
- What's the payload shape — `{ [key]: { metas: [...] } }`?

---

## 8. Postgres Changes

**Assumption H1.** One `postgres_changes` entry in join config = one
server-side filter = one subscription. Multiple entries can be combined
OR-style in a single join. (§5.2, §5.3 "independent subscription")

- Confirmed multiple entries per join are allowed?
- If two entries overlap (e.g., both match an INSERT on `messages`), does
  the server emit duplicate events, deduplicate, or something else?

**Assumption H2.** Filter wire format is `column=op.value`. Exactly one
clause per entry. No `AND`/`OR`/parenthesization. (§5.2 "single optional
clause", Decision 12)

- Confirmed single-clause-only? Even if multiple `filter:` fields were
  supplied, would only one be honored?
- Are there plans to support `AND` composition? (So we know whether to
  leave room in the API.)

**Assumption H3.** Supported operators are `eq`, `neq`, `gt`, `gte`, `lt`,
`lte`, `in`. (§5.2 Filter factories)

- Confirmed the full list? Is `is.null` / `is.not.null` supported?
- Is `like` / `ilike` / `match` supported?
- For `in`: what's the max list length?
- Value encoding: how should UUIDs, ISO dates, numbers, booleans, NULLs
  be serialized in `column=op.value`? Any escaping for commas in `in`?

**Assumption H4.** Event filtering on `INSERT`/`UPDATE`/`DELETE`/`*` is
exact — `*` subscribes to all three; anything else subscribes to only
that one. (§5.3 PostgresChangeEvent)

- Confirmed? Are there other event types (TRUNCATE, etc.) we should
  handle?

**Assumption H5.** For `UPDATE`, the server sends both `old_record` and
`record`. For `DELETE`, only `old_record`. For `INSERT`, only `record`.
(§5.3 `InsertAction`/`UpdateAction`/`DeleteAction`)

- Confirmed? Is `old_record` always populated on UPDATE, or only when
  `REPLICA IDENTITY FULL` is set on the table?
- If `REPLICA IDENTITY` is not `FULL`, what's returned for DELETE? (Just
  PKs, or entire row?)
- Schema column order and types match what PostgREST returns for selects?

**Assumption H6.** If the underlying publication doesn't include a table
or column, events silently don't fire — no error at join time. (§5.3)

- Confirmed? Or does the server reject the join with an error if the
  table/column doesn't exist in `supabase_realtime` publication?

**Assumption H7.** Postgres change subscriptions are automatically
re-registered on rejoin — the client just re-sends the same join config.
(§9.2 "postgres change subscriptions are restored")

- Confirmed? Any gaps during rejoin that could lose events? If so, is
  there a replay/cursor mechanism like broadcast replay?

---

## 9. Auth / Token Rotation

**Assumption I1.** The Phoenix event name for pushing a new token is
`access_token` with `{ access_token: "..." }`. Server ACKs with `phx_reply`.
(§6.3 updateToken)

- Confirmed event name and payload shape?
- Is the response always a `phx_reply` on the top-level socket (not
  per-channel)? Or per-channel?
- What does the server do if the new token has different claims
  (different `sub`, expired `exp`)?

**Assumption I2.** On `token_expired`, the server sends a message the
client can distinguish from other errors, and the operation that triggered
it fails with a retryable error. (§6.3 "Reactive path")

- What's the exact wire signal — a `phx_error` with `reason: "token_expired"`?
  On which channel / on the socket itself?
- Does `token_expired` close the socket, close the individual channel, or
  just reject the in-flight push?
- After pushing a refreshed token, is the retry on the same original
  request, or do we need to resubscribe?

**Assumption I3.** JWT `exp` is not parsed or enforced client-side — the
SDK reacts only to server-sent `token_expired`. (Decision 9 "No JWT
parsing in the SDK")

- Is this safe, or is there meaningful latency between local expiry and
  server detection that would justify proactive rotation?

---

## 10. Error Taxonomy

**Assumption J1.** All server-sent errors arrive as `phx_error` /
`phx_reply {status: "error"}` with a `reason: String` field. No structured
error codes. (§7 RealtimeError)

- Is there a stable set of `reason` strings we can pattern-match to map
  into our error cases? Example: `"unauthorized"`, `"rate_limited"`,
  `"token_expired"`, `"server_error"`, etc.
- If the set is unstable: can we get a structured `code` field added?

**Assumption J2.** Server close codes on unexpected socket close are
meaningful and distinct for auth vs transient vs policy violations.

- What close codes does the server use, and for which scenarios?
  (E.g., 4001 = auth, 4003 = rate limit, 4008 = policy, etc.)
- Any close code that means "do not reconnect" vs "reconnect with backoff"?

---

## 11. Rate Limits and Quotas

**Assumption K1.** Rate limits exist but are not surfaced in the v3 API
except via `.rateLimited(retryAfter:)`. (§7)

- What are the default server-side limits — messages/sec per channel,
  connections per project, topics per socket, presence entries per
  channel, presence state size?
- When exceeded via WS: what's the wire signal? A `phx_error` with
  `reason: "rate_limited"` + a `retry_after` field? Connection close?
- When exceeded via HTTP: `429` with `Retry-After` header?

**Assumption K2.** There's no per-client connection cooldown — clients
can reconnect immediately after any close. (§9.1 ReconnectionPolicy)

- Is there a server-side "too many reconnects" throttle? If so, what
  delays does it enforce and how are they communicated?

---

## 12. Ordering and Delivery

**Assumption L1.** Within a single topic, for a single client, events
arrive in the order the server processed them. Across topics, no ordering
guarantee. (Implicit throughout)

- Confirmed per-topic-per-client ordering?
- For postgres_changes specifically: does the server guarantee WAL order
  within a table, or can concurrent transactions reorder?

**Assumption L2.** Broadcasts and postgres_changes on the same topic
interleave arbitrarily. (§3, §5)

- Confirmed? No implicit ordering between them?

**Assumption L3.** Presence `diff` events and broadcast events on the
same topic interleave arbitrarily.

- Confirmed?

---

## 13. Reconnection / Resilience

**Assumption M1.** After a client reconnect, the server has no memory of
prior subscriptions — the client must re-send all `phx_join`s. (§9.2)

- Confirmed, no session resumption?
- If session resumption is coming in a future version, is there a
  protocol hint we should leave room for?

**Assumption M2.** The server does not emit a "you missed events while
disconnected" signal. Gaps are silent and the client cannot detect them
without broadcast replay. (§3.1 "Gaps are inherent")

- Confirmed no gap-detection mechanism?

---

## 14. App Lifecycle

**Assumption N1.** The WebSocket can survive short iOS/macOS
background-foreground transitions without the server terminating the
connection. (§9.3 handleAppLifecycle)

- What's the server-side idle/heartbeat timeout that determines how long
  a backgrounded app can stay connected before the server closes?
- Is there a way to "pause" a connection server-side without closing it?
  (Probably not, but worth asking.)

---

## 15. Protocol Limits (Hard Numbers We Want to Document)

Please confirm or correct:

| Limit | Assumed | Source |
| ----- | ------- | ------ |
| Max topics per WebSocket | ? | |
| Max concurrent WebSockets per project | ? | |
| Max broadcast payload size (JSON) | ? | |
| Max broadcast payload size (binary) | ? | |
| Max presence metas per key | ? | |
| Max presence state bytes per channel | ? | |
| Max `postgres_changes` entries per join | ? | |
| Max `in` list length in filter | ? | |
| Broadcast replay retention window | ? | |
| Broadcast replay max limit | ? | |
| Default heartbeat timeout (server side) | ? | |
| Rate limit: broadcasts/sec per channel | ? | |
| Rate limit: joins/sec per socket | ? | |

---

## 16. Open Design Questions that Depend on Backend

These are v3 API decisions we deliberately deferred — the answer from
backend may change our preference.

1. **Unbounded broadcast buffers.** We picked unbounded per-consumer
   buffers (§3.1, Decision 7). If the server drops misbehaving subscribers
   itself under backpressure, we could rely on that rather than asking
   clients to opt into a drop policy later.
2. **Automatic retry on `token_expired`.** We retry once (§6.3, Decision 10).
   If the server already handles token rotation idempotently (i.e., the same
   request can be replayed safely), we could retry more aggressively or
   never.
3. **HTTP broadcast batching.** We expose a batch form (§3.3). If the
   server's batch endpoint has materially different rate limits or failure
   semantics than the single form, we should document that.
4. **Presence key ownership.** We pushed presence key to channel-level
   config (§4, Decision 17). If the backend plans to support per-track
   presence keys natively, we'd revisit.

---

## How to respond

Ideal format: for each question, either "yes, confirmed", "no, here's the
actual behavior", or "undefined — please don't rely on it". For the
numeric limits table, fill in concrete numbers or "no hard limit".
