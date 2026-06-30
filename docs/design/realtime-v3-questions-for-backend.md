# Realtime v3 - Questions for the Realtime Backend Team

Each section pairs **an assumption baked into the v3 Swift design** with
**the question(s) that need to be validated**. If an assumption is wrong, the
linked sections in `realtime-v3.md` need revisiting.

## Backend source audit

Findings below were checked against the local Realtime backend checkout at
`/Users/guilherme/src/github.com/supabase/realtime` on 2026-06-27. Source paths
are relative to that backend repository.

---

## 1. Connection / Socket

**Assumption A1.** WebSocket auth is a single `apikey` query param / header.
No additional handshake. (§1.1, §6.1)

- Is `apikey` the only required auth on connect, or should we also send
  `Authorization: Bearer <jwt>` and/or `vsn` as a query param?
- Are there any required subprotocols (`Sec-WebSocket-Protocol`) we should
  be setting?

**Finding.** Mostly confirmed, with one important header-name distinction. The
WebSocket connect path accepts an API key from the `apikey` query parameter or
the `x-api-key` header, validates it as a token/API key, authorizes the
connection, and does not read `Authorization` for the WebSocket handshake. The
endpoint also receives `x_headers` and `uri` connect info. `vsn` is used by the
Phoenix serializer negotiation, not as auth. No required WebSocket subprotocol
was found in endpoint configuration. Join payloads can additionally carry
`access_token` / `user_token`, but those are channel-level payload fields.

Sources: `lib/realtime_web/channels/user_socket.ex:51`,
`lib/realtime_web/channels/user_socket.ex:67`,
`lib/realtime_web/channels/user_socket.ex:132`,
`lib/realtime_web/channels/user_socket.ex:146`,
`lib/realtime_web/endpoint.ex:16`,
`lib/realtime_web/endpoint.ex:20`,
`lib/realtime_web/channels/payloads/join.ex:11`.

**Assumption A2.** `vsn=2.0.0` is the preferred wire version and is stable.
(§1.2, §11, Config.protocolVersion)

- Is v2 (binary broadcast frames + array-encoded messages) the recommended
  default for new clients?
- Any plans for v3? If so, what's the rough shape, and should we design an
  escape hatch for it?
- Are there server deployments still pinned to v1 where v2 would break?

**Finding.** Confirmed that Realtime registers the custom v2 serializer for
`~> 2.0.0` while still supporting Phoenix v1 JSON serializer for `~> 1.0.0`.
No v3 serializer or protocol branch was found in the backend code. Longpoll is
configured separately and does not use the custom Realtime v2 serializer.

Sources: `lib/realtime_web/endpoint.ex:16`, `lib/realtime_web/endpoint.ex:35`,
`lib/realtime_web/socket/v2_serializer.ex:1`,
`test/support/generators.ex:338`.

**Assumption A3.** Default heartbeat interval 25s is safe. (§1.2, §6.4)

- What's the server-side heartbeat timeout (after how many missed
  heartbeats does the server close the socket)?
- Are there Cloudflare/LB-level idle timeouts that could close an
  otherwise-healthy socket? If so, what's the max safe heartbeat interval?

**Finding.** Not fully confirmed from Realtime application code. The endpoint
does not set a Realtime-specific WebSocket heartbeat timeout, so heartbeat
timing appears to rely on Phoenix/Cowboy defaults and deployment/LB behavior.
The only Realtime-specific socket timeout found is `NO_CHANNEL_TIMEOUT_IN_MS`,
which kills a transport that has no open channels after the tracker interval;
that is not a heartbeat timeout. The backend repo does not answer Cloudflare or
load-balancer idle timeout values.

Sources: `lib/realtime_web/endpoint.ex:16`, `config/runtime.exs:80`,
`lib/realtime/application.ex:148`,
`lib/realtime_web/channels/realtime_channel/tracker.ex:60`.

**Assumption A4.** Heartbeat RTT is exposed as `phx_reply` latency and is
the canonical "is the connection healthy" signal. (§6.4, `ConnectionStatus.latency`)

- Is `phx_reply` the right signal, or does the server also push periodic
  presence/state messages we could use?
- Is there any server-initiated "ping" the client is expected to respond to?

**Finding.** Confirmed as Phoenix-standard heartbeat behavior. Tests and helpers
send `"heartbeat"` on the `"phoenix"` topic. No Realtime-specific
server-initiated ping or periodic presence/state health message was found.

Sources: `test/support/websocket_client.ex:60`,
`lib/realtime_web/channels/realtime_channel.ex:43`,
`lib/realtime_web/endpoint.ex:16`.

---

## 2. Channel Join / Leave

**Assumption B1.** A client may have at most one live subscription per
topic per socket. A second `phx_join` on the same topic while one is live
is rejected or ignored. (§2.1, §2.3)

- Confirmed? If a second `phx_join` is sent for an already-joined topic,
  what does the server do - error, overwrite, or dedupe silently?
- Does the server enforce a max number of topics per socket? What's the limit?

**Finding.** Partially unresolved from Realtime code. Realtime enforces a max
number of channels per transport, but it does not implement an explicit
"one channel per topic" check in `RealtimeChannel`; duplicate topic behavior is
delegated to Phoenix channel machinery. The per-client channel limit is
tenant-configured as `max_channels_per_client` and defaults to 100.

Sources: `lib/realtime_web/channels/realtime_channel.ex:634`,
`lib/realtime_web/channels/realtime_channel.ex:653`,
`lib/realtime_web/channels/realtime_channel.ex:666`,
`config/runtime.exs:98`.

**Assumption B2.** `phx_leave` is always ACKed by the server before the
server-side state is torn down. (§2.3 "await-to-ack")

- Is `phx_leave` always ACKed? Under what conditions can it not be
  (e.g., server shutdown mid-leave)?
- After ACK, is it safe to assume no further events for that topic will
  arrive on this socket?
- If the socket drops mid-leave, what's the server's cleanup behavior?
  (We need to know whether a reconnecting client should re-send leave
  or just skip it.)

**Finding.** Realtime has no custom `phx_leave` handler; leave behavior is
Phoenix channel behavior. Integration tests assert that `leave` produces
`phx_close`. On termination, Realtime untracks the transport/channel count, and
Postgres CDC subscriptions are cleaned up by the subscription manager. If the
transport drops mid-leave, cleanup is process-termination driven rather than
requiring the client to resend leave.

Sources: `test/integration/tracker_test.exs:31`,
`lib/realtime_web/channels/realtime_channel.ex:617`,
`lib/realtime_web/channels/realtime_channel/tracker.ex:18`,
`lib/realtime_web/channels/realtime_channel/tracker.ex:73`,
`lib/extensions/postgres_cdc_rls/subscription_manager.ex:189`,
`lib/extensions/postgres_cdc_rls/subscription_manager.ex:216`,
`lib/extensions/postgres_cdc_rls/subscriptions.ex:170`.

**Assumption B3.** A `phx_join` immediately after `phx_leave` on the same
topic is valid and produces a fresh subscription. (§2.3 "pipelined re-acquire")

- If the client sends `phx_leave` then `phx_join` back-to-back (before
  leave is ACKed), does the server queue them in order, reject the join,
  or race them?
- Is there a minimum cooldown between leave and rejoin on the same topic?

**Finding.** No Realtime-specific cooldown or queueing rule was found. Back to
back leave/join ordering is therefore Phoenix-level behavior. For deterministic
client behavior, the Swift design should continue to wait for the leave
completion/close before treating the next join as a fresh subscription.

Sources: `lib/realtime_web/channels/realtime_channel.ex:43`,
`lib/realtime_web/channels/realtime_channel.ex:617`,
`test/integration/tracker_test.exs:31`.

**Assumption B4.** Dropping a client socket without leaving joined
channels is safe - the server GCs subscriptions within some finite window.
(§2.1 "leaked-channel warning")

- What's the server-side cleanup delay for abandoned subscriptions?
- Are there billing/quota implications for abandoning vs leaving?
  (We want to know how loud our leak warning should be.)

**Finding.** Confirmed that cleanup is finite and process-driven. Channel
termination decrements the transport tracker; Phoenix Presence entries are tied
to the channel process; Postgres subscriptions include the channel pid and are
removed/updated by subscription management. A separate tracker kills transports
that have no channels after `NO_CHANNEL_TIMEOUT_IN_MS` (default 10 minutes),
but a dropped transport should tear down channel processes sooner. No billing
distinction between abandoned vs explicitly left channels was found in code.

Sources: `lib/realtime_web/channels/realtime_channel.ex:617`,
`lib/realtime_web/channels/realtime_channel/tracker.ex:73`,
`config/runtime.exs:80`,
`lib/realtime_web/channels/realtime_channel.ex:819`,
`lib/extensions/postgres_cdc_rls/subscription_manager.ex:189`,
`lib/extensions/postgres_cdc_rls/subscription_manager.ex:216`,
`lib/realtime_web/channels/realtime_channel/presence_handler.ex:130`.

---

## 3. Channel Join Config

**Assumption C1.** The entire `config` object is frozen at `phx_join` time.
No way to mutate `broadcast.ack`, `self`, `replay`, `presence.key`, or
`postgres_changes` mid-subscription without leaving and rejoining.
(§2.2 "options are locked at creation")

- Confirmed? Are any of these fields mutable mid-flight?
- If a caller needs to change `postgres_changes` filters, is the correct
  pattern always leave + rejoin, or is there a `phx_update`-style event?

**Finding.** Confirmed. Join config is parsed into socket assigns at join time.
The only channel events handled after join are broadcast, presence, token
rotation (`access_token`), and fallback/error cases. No `phx_update` or
Realtime-specific config mutation event was found.

Sources: `lib/realtime_web/channels/realtime_channel.ex:43`,
`lib/realtime_web/channels/realtime_channel.ex:140`,
`lib/realtime_web/channels/realtime_channel.ex:439`,
`lib/realtime_web/channels/realtime_channel.ex:469`,
`lib/realtime_web/channels/realtime_channel.ex:520`,
`lib/realtime_web/channels/payloads/config.ex:20`.

**Assumption C2.** `private: true` channels go through RLS at join time
and reject if the JWT is invalid or lacks permission. (§2.2)

- What's the exact error the server returns on unauthorized private-channel
  join? (`reason` string format, so we can map to `.authenticationFailed`
  vs `.channelJoinRejected`.)
- Does `private: true` have implications for broadcast and postgres_changes
  behavior beyond the join check?

**Finding.** Confirmed, and `private: true` has ongoing authorization effects.
Private join computes authorization policies and rejects missing read
permission with a message shaped like
`You do not have permissions to read from this Channel topic: <topic>`. Private
broadcast writes and private presence read/write are also checked against RLS.
Postgres changes are separately authorized through CDC subscription claims and
RLS.

Sources: `lib/realtime_web/channels/realtime_channel.ex:906`,
`lib/realtime_web/channels/realtime_channel.ex:929`,
`lib/realtime_web/channels/realtime_channel/broadcast_handler.ex:25`,
`lib/realtime_web/channels/realtime_channel/presence_handler.ex:85`,
`lib/realtime/tenants/single_broadcast.ex:153`,
`lib/extensions/postgres_cdc_rls/subscriptions.ex:60`.

---

## 4. Broadcast - WebSocket

**Assumption D1.** `broadcast.ack: true` means every broadcast send gets a
`phx_reply` from the server. `ack: false` means none. (§3.2, BroadcastOptions.acknowledge)

- Confirmed? What's the exact correlation mechanism - by `ref`?
- What's a reasonable default `broadcastAckTimeout`? (We picked 5s.)

**Finding.** Confirmed for accepted public broadcasts and authorized private
broadcasts. The handler returns `{:reply, :ok, socket}` when `ack_broadcast` is
true and `{:noreply, socket}` when false, so correlation is the normal Phoenix
push `ref`. Payload-size errors also reply only when ack is enabled. One edge:
an unauthorized private broadcast path returns `noreply`, so an acking client
could time out instead of receiving a structured authorization error.

Sources: `lib/realtime_web/channels/realtime_channel/broadcast_handler.ex:21`,
`lib/realtime_web/channels/realtime_channel/broadcast_handler.ex:25`,
`lib/realtime_web/channels/realtime_channel/broadcast_handler.ex:51`,
`lib/realtime_web/channels/realtime_channel/broadcast_handler.ex:62`,
`lib/realtime_web/channels/realtime_channel/broadcast_handler.ex:90`.

**Assumption D2.** `self: true` echoes broadcasts back to the sender.
`self: false` does not. This is channel-wide, not per-message. (§3.2, Decision 23)

- Confirmed channel-wide only, no per-message override?
- Ordering guarantee: if I broadcast 3 messages with `self: true`, are the
  echoes guaranteed to arrive in send order?

**Finding.** Confirmed channel-wide. `self_broadcast` is assigned from join
config and the handler chooses `pubsub_broadcast` when true or
`pubsub_broadcast_from(self())` when false. No per-message override was found.
The code does not document or enforce a formal ordering guarantee beyond normal
single-process/PubSub processing.

Sources: `lib/realtime_web/channels/realtime_channel.ex:145`,
`lib/realtime_web/channels/realtime_channel/broadcast_handler.ex:120`,
`lib/realtime_web/channels/realtime_channel/message_dispatcher.ex:70`.

**Assumption D3.** v2 protocol sends broadcast payloads as binary frames
(opcode `0x02`), type byte `0x03` (client-to-server) / `0x04` (server-to-client).
Non-broadcast messages are text frames with JSON arrays. (§3.1, memory:
protocol 2.0.0)

- Confirmed? What's the exact binary framing - is the payload length
  length-prefixed, or end-of-frame delimited?
- Is there a max binary frame size the server enforces?

**Finding.** Confirmed for user broadcast frames, with extra frame types to
document. Client-to-server user broadcast uses type byte `3`; server-to-client
user broadcast uses type byte `4`. The frame stores 1-byte lengths for
topic/event/metadata fields and the payload is end-of-frame delimited. v2 also
uses type byte `2` for generic binary `%Phoenix.Socket.Broadcast{}` payloads and
type byte `0` for generic binary pushes. Endpoint `max_frame_size` is
5,000,000 bytes. Topic, event, and metadata JSON fields are each limited to 255
bytes by the serializer's 1-byte size fields.

Sources: `lib/realtime_web/socket/v2_serializer.ex:9`,
`lib/realtime_web/socket/v2_serializer.ex:19`,
`lib/realtime_web/socket/v2_serializer.ex:27`,
`lib/realtime_web/socket/v2_serializer.ex:47`,
`lib/realtime_web/socket/v2_serializer.ex:158`,
`lib/realtime_web/socket/v2_serializer.ex:179`,
`lib/realtime_web/endpoint.ex:20`.

**Assumption D4.** Arbitrary `Data` can be broadcast as a binary payload
without JSON encoding. (§3.2, Decision 25)

- Does the server inspect broadcast payloads, or is any byte string valid?
- Any size limits specific to binary vs JSON broadcasts?

**Finding.** Confirmed with size limits. v2 user broadcast payloads can carry
raw binary and the server preserves the encoding. Payload contents are not
inspected beyond decoding the frame and checking tenant payload size. JSON and
binary broadcasts use the same tenant payload-size check, and WebSocket frames
also hit the endpoint `max_frame_size`.

Sources: `lib/realtime_web/socket/v2_serializer.ex:179`,
`lib/realtime_web/channels/realtime_channel/broadcast_handler.ex:146`,
`lib/realtime_web/channels/realtime_channel/broadcast_handler.ex:157`,
`lib/realtime/tenants.ex:532`,
`lib/realtime_web/endpoint.ex:20`.

**Assumption D5.** Broadcast delivery is best-effort - no retry, no queue,
no ordering guarantees across topics. Within a single topic + sender,
order is preserved. (§3.1 "streams pause silently during reconnection")

- Within-topic, within-sender order: guaranteed? (We document it as such.)
- Any cross-topic ordering guarantees we should not assume away?
- Are there rate limits? If so, what does the server return when exceeded?

**Finding.** Best-effort/no cross-topic ordering is consistent with the code.
Realtime uses Phoenix PubSub and fastlane dispatch; no retry or durable queue
for live WebSocket broadcast delivery was found. The code does not state a
contractual within-topic ordering guarantee, although messages from the same
channel process are processed sequentially. Tenant message-rate limits exist.
When a WebSocket client exceeds messages/sec, Realtime pushes a `"system"` error
and stops the channel.

Sources: `lib/realtime_web/channels/realtime_channel/broadcast_handler.ex:120`,
`lib/realtime_web/channels/realtime_channel/message_dispatcher.ex:70`,
`lib/realtime_web/channels/realtime_channel.ex:298`,
`lib/realtime_web/channels/realtime_channel.ex:776`,
`config/runtime.exs:100`.

---

## 5. Broadcast - HTTP Endpoint

**Assumption E1.** `POST /realtime/v1/api/broadcast` is the correct endpoint
for one-shot broadcasts without opening a WS. (§3.3 httpBroadcast)

- Is that the canonical path? Is there a versioned alternative?
- Request body shape - batch-only (`{ messages: [...] }`) or single also
  accepted?
- Response shape on success (200? 204? body?)
- Error shape - structured JSON with `code`/`message`?

**Finding.** Internally the Phoenix router exposes `POST /api/broadcast` for
batch and `POST /api/broadcast/:topic/events/:event` for single-message
broadcasts; deployed Supabase paths are expected to add the `/realtime/v1`
prefix outside this router. Batch accepts `{ "messages": [...] }`; the single
endpoint accepts JSON or octet-stream payloads. Success is `202 Accepted` with
an empty body. HTTP error bodies are not uniformly structured with stable
`code` fields; common cases use JSON `message`, validation errors, or empty
responses depending on controller/fallback path.

Sources: `lib/realtime_web/router.ex:111`, `lib/realtime_web/router.ex:117`,
`lib/realtime_web/controllers/broadcast_controller.ex:14`,
`lib/realtime_web/controllers/broadcast_controller.ex:35`,
`lib/realtime_web/controllers/broadcast_single_controller.ex:21`,
`lib/realtime_web/controllers/broadcast_single_controller.ex:78`.

**Assumption E2.** HTTP broadcast uses the same `apikey` and JWT auth as
the WebSocket. (§3.3 "Auth uses the same `APIKeySource`")

- Confirmed? Header names: `apikey`, `Authorization: Bearer <jwt>`?
- Does HTTP broadcast honor RLS for private topics? If the JWT lacks
  permission, what's the error?

**Finding.** Partially different from WebSocket. HTTP tenant auth reads
`Authorization: Bearer <token>` first, then `apikey` header; it does not use the
WebSocket `x-api-key` header in the plug that authenticates broadcast requests.
Private single-message broadcast checks write authorization and returns
forbidden on missing permission. Private batch broadcast groups messages by
topic and checks write authorization, but unauthorized private messages are
skipped while the batch can still return success for the remaining work.

Sources: `lib/realtime_web/plugs/auth_tenant.ex:34`,
`lib/realtime_web/plugs/auth_tenant.ex:65`,
`lib/realtime/tenants/single_broadcast.ex:153`,
`lib/realtime/tenants/single_broadcast.ex:183`,
`lib/realtime/tenants/batch_broadcast.ex:55`,
`lib/realtime/tenants/batch_broadcast.ex:80`.

**Assumption E3.** HTTP broadcast emits the message to all WS subscribers
on that topic exactly as if a WS client had sent it. (§3.3)

- Confirmed? Does `self: true` (if the sender happens to also have a WS
  subscription to the topic) apply to HTTP-originated broadcasts?

**Finding.** Confirmed that HTTP broadcast publishes through the same
tenant/topic PubSub path used by WebSocket subscribers. HTTP has no originating
channel process, so `self` suppression does not apply; all matching subscribers
receive the broadcast subject to topic and authorization behavior.

Sources: `lib/realtime/tenants/batch_broadcast.ex:129`,
`lib/realtime/tenants/single_broadcast.ex:222`,
`lib/realtime_web/channels/realtime_channel/message_dispatcher.ex:70`.

**Assumption E4.** HTTP broadcast has its own rate limits distinct from WS.

- What are they? How are they communicated - `429` with `Retry-After`
  header? Any per-topic limits vs per-project?

**Finding.** Mostly false. HTTP broadcast uses the tenant events/sec limit also
used by WebSocket message accounting. HTTP additionally has a plug that sets
`x-rate-rolling`, `x-rate-limit`, and `x-rate-limit-remaining` headers and
returns `429` JSON `{ "message": "Too many requests" }`. No `Retry-After`
header or per-topic limit was found.

Sources: `lib/realtime_web/plugs/rate_limiter.ex:13`,
`lib/realtime_web/plugs/rate_limiter.ex:29`,
`lib/realtime/tenants/batch_broadcast.ex:170`,
`lib/realtime/tenants/single_broadcast.ex:211`,
`config/runtime.exs:100`.

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

**Finding.** Confirmed join-time-only, and private-only. Replay is read from
join config; no mid-subscription replay event was found. Public-channel replay
is rejected as `:invalid_replay_channel`. Default limit is 25; hard max is 25
and min is 1. Messages are queried in descending `inserted_at` order then
reversed before being pushed, so replay delivery is oldest-to-newest within the
returned window. Retention cleanup deletes message partitions older than about
72 hours; an older `since` returns the remaining retained window rather than a
special "too old" error. Replay is scheduled during join and live messages with
replayed IDs are skipped to avoid duplicates, but the code should be treated as
"join-time replay before normal live consumption" rather than a durable cursor.

Sources: `lib/realtime_web/channels/realtime_channel.ex:87`,
`lib/realtime_web/channels/realtime_channel.ex:962`,
`lib/realtime_web/channels/realtime_channel.ex:966`,
`lib/realtime_web/channels/realtime_channel.ex:287`,
`lib/realtime/messages.ex:10`,
`lib/realtime/messages.ex:22`,
`lib/realtime/messages.ex:51`,
`lib/realtime/messages.ex:69`,
`lib/realtime_web/channels/realtime_channel/message_dispatcher.ex:162`.

---

## 7. Presence

**Assumption G1.** Phoenix presence allows multiple `track` calls from the
same socket under the same presence key, each registering a distinct meta
entry. (§4 multi-track support, Decision 16)

- Confirmed? Or does `track` overwrite any prior meta for the same key?
- If multi-meta: is there a server-enforced max metas per key?

**Finding.** False for same socket + same key. The presence handler tracks a
single payload for the channel process and presence key. A later `track` from
the same pid/key updates the existing meta via `Presence.update`; same payload
is a no-op. Multiple different sockets can share a key and produce multiple
metas through Phoenix Presence, but the Swift "multiple handles from the same
socket/key" assumption is not supported by this backend path.

Sources: `lib/realtime_web/channels/realtime_channel/presence_handler.ex:141`,
`lib/realtime_web/channels/realtime_channel/presence_handler.ex:162`,
`lib/realtime_web/channels/realtime_channel/presence_handler.ex:189`,
`test/realtime_web/channels/realtime_channel/presence_handler_test.exs:136`,
`test/realtime_web/channels/realtime_channel/presence_handler_test.exs:163`.

**Assumption G2.** `presence.key` in join config sets this client's
presence key. If nil, the server generates one (random/per-connection).
(§4 "Presence key source", Decision 17, 45)

- Confirmed the server generates if nil? What's the format
  (UUID, random string)?
- Is the generated key stable across reconnects of the same socket, or
  fresh every connect?

**Finding.** Confirmed. If `presence.key` is nil or empty, the join payload
helper generates `UUID.uuid1()`. That happens per join, so it is not stable
across reconnect/rejoin unless the client supplies its own key.

Sources: `lib/realtime_web/channels/payloads/join.ex:35`,
`lib/realtime_web/channels/payloads/presence.ex:10`.

**Assumption G3.** There's an explicit "untrack" mechanism (the
`presence.untrack` event, or similar). Dropping all metas requires an
explicit untrack - merely going silent does not remove presence.
(§4 PresenceHandle.cancel)

- Confirmed? What's the wire-level untrack event?
- Is untrack ACKed? (We document await-to-ack.)
- If I have 3 tracks and want to untrack one, how does the server know
  which meta to remove - meta content match, or a per-track ref?

**Finding.** Confirmed with a different event shape than the assumption text.
The wire event is channel event `"presence"` with payload field
`"event": "untrack"`. The channel handler replies `:ok` on valid presence
events, so untrack is acked through the normal push `ref`. It removes the
current channel process' single meta for the configured key; there is no
per-track ref because same-socket multi-track is not represented.

Sources: `lib/realtime_web/channels/realtime_channel.ex:469`,
`lib/realtime_web/channels/realtime_channel.ex:496`,
`lib/realtime_web/channels/realtime_channel/presence_handler.ex:69`,
`lib/realtime_web/channels/realtime_channel/presence_handler.ex:130`,
`test/realtime_web/channels/realtime_channel/presence_handler_test.exs:236`.

**Assumption G4.** On `phx_leave`, the server removes all presence metas
for that socket+topic without requiring explicit untracks. (§4
"when `channel.leave()` is called, all outstanding tracks are implicitly
torn down server-side")

- Confirmed? Or must we send explicit untracks before leave?

**Finding.** Confirmed by process ownership. Presence is tracked against the
channel process (`self()`), so channel termination/leave removes that process'
presence entries through Phoenix Presence. No explicit untrack-before-leave
requirement was found.

Sources: `lib/realtime_web/channels/realtime_channel/presence_handler.ex:158`,
`lib/realtime_web/channels/presence.ex:8`,
`lib/realtime_web/channels/realtime_channel.ex:617`,
`test/realtime_web/channels/realtime_channel/presence_handler_test.exs:184`.

**Assumption G5.** Presence is **not** auto-restored by the server on
rejoin. The client must re-send `track` for each live state after the
rejoin `phx_reply`. (§4 "auto re-track on reconnect", §9.2, Decision 18)

- Confirmed the server does NOT remember presence across reconnects?
- If the server does remember: we need to either skip re-tracking
  (optimal) or detect and reconcile (harder).

**Finding.** Confirmed. Presence state is tied to the channel process and the
generated key is per join unless supplied by the client. No server session
state was found that restores presence after reconnect/rejoin.

Sources: `lib/realtime_web/channels/realtime_channel/presence_handler.ex:158`,
`lib/realtime_web/channels/payloads/join.ex:35`,
`lib/realtime_web/channels/realtime_channel.ex:617`.

**Assumption G6.** `presence_state` (snapshot) arrives once per join;
`presence_diff` arrives for every subsequent change. (§4 `observe` vs `diffs`)

- Confirmed? Does the snapshot always arrive even when joining an empty
  presence set?
- What's the payload shape - `{ [key]: { metas: [...] } }`?

**Finding.** Snapshot is sent on join only when presence is enabled in join
config or enabled by tenant/private authorization. If presence config is
disabled, no initial `presence_state` is pushed; later `track` can still enable
presence and produce diffs. Snapshot/diff payloads are Phoenix Presence grouped
maps shaped like keys to `%{metas: [...]}`; empty state is `%{}`.

Sources: `lib/realtime_web/channels/realtime_channel.ex:169`,
`lib/realtime_web/channels/realtime_channel/presence_handler.ex:28`,
`lib/realtime_web/channels/realtime_channel/presence_handler.ex:193`,
`test/integration/rt_channel/presence_test.exs:23`,
`test/integration/rt_channel/presence_test.exs:61`,
`test/integration/rt_channel/presence_test.exs:74`.

---

## 8. Postgres Changes

**Assumption H1.** One `postgres_changes` entry in join config = one
server-side filter = one subscription. Multiple entries can be combined
OR-style in a single join. (§5.2, §5.3 "independent subscription")

- Confirmed multiple entries per join are allowed?
- If two entries overlap (e.g., both match an INSERT on `messages`), does
  the server emit duplicate events, deduplicate, or something else?

**Finding.** Multiple entries per join are allowed. Each entry gets an id and is
inserted as a subscription. For the new API, overlapping entries do not produce
duplicate WebSocket messages; one `"postgres_changes"` message includes an
`ids` array listing the matching subscription ids for that WAL change.

Sources: `lib/realtime_web/channels/realtime_channel.ex:819`,
`lib/realtime_web/channels/realtime_channel.ex:856`,
`lib/realtime_web/channels/realtime_channel.ex:885`,
`lib/extensions/postgres_cdc_rls/message_dispatcher.ex:11`,
`test/e2e/realtime-check.ts:1183`.

**Assumption H2.** Filter wire format is `column=op.value`. Exactly one
clause per entry. No `AND`/`OR`/parenthesization. (§5.2 "single optional
clause", Decision 12)

- Confirmed single-clause-only? Even if multiple `filter:` fields were
  supplied, would only one be honored?
- Are there plans to support `AND` composition? (So we know whether to
  leave room in the API.)

**Finding.** False. One `filter` string may contain multiple comma-separated
clauses, parsed as AND. The parser splits top-level commas while respecting
parentheses and quoted strings. A `not.` prefix is also supported. OR
composition was not found.

Sources: `lib/extensions/postgres_cdc_rls/subscriptions.ex:241`,
`lib/extensions/postgres_cdc_rls/subscriptions.ex:390`,
`lib/extensions/postgres_cdc_rls/subscriptions.ex:397`,
`lib/extensions/postgres_cdc_rls/subscriptions.ex:439`,
`test/e2e/realtime-check.ts:1523`,
`test/e2e/realtime-check.ts:1551`.

**Assumption H3.** Supported operators are `eq`, `neq`, `gt`, `gte`, `lt`,
`lte`, `in`. (§5.2 Filter factories)

- Confirmed the full list? Is `is.null` / `is.not.null` supported?
- Is `like` / `ilike` / `match` supported?
- For `in`: what's the max list length?
- Value encoding: how should UUIDs, ISO dates, numbers, booleans, NULLs
  be serialized in `column=op.value`? Any escaping for commas in `in`?

**Finding.** Incomplete list. Backend supports `eq`, `neq`, `lt`, `lte`, `gt`,
`gte`, `in`, `like`, `ilike`, `is`, `match`, `imatch`, and `isdistinct`, with
`not.` negation. `is` supports `null`, `true`, `false`, and `unknown`. `in`
requires parenthesized values and enforces a maximum of 100 values. Quoted
values are parsed with quote/backslash escaping; commas inside quoted strings or
parentheses are not treated as clause separators.

Sources: `lib/extensions/postgres_cdc_rls/subscriptions.ex:19`,
`lib/extensions/postgres_cdc_rls/subscriptions.ex:439`,
`lib/extensions/postgres_cdc_rls/subscriptions.ex:464`,
`lib/extensions/postgres_cdc_rls/subscriptions.ex:476`,
`lib/realtime/tenants/repo/migrations/20260626120000_readd_postgrest_filter_ops.ex:61`,
`lib/realtime/tenants/repo/migrations/20260527120000_add_select_columns_to_subscriptions.ex:75`,
`test/e2e/realtime-check.ts:1249`.

**Assumption H4.** Event filtering on `INSERT`/`UPDATE`/`DELETE`/`*` is
exact - `*` subscribes to all three; anything else subscribes to only
that one. (§5.3 PostgresChangeEvent)

- Confirmed? Are there other event types (TRUNCATE, etc.) we should
  handle?

**Finding.** `INSERT`, `UPDATE`, `DELETE`, and `*` are the only event filters in
the current subscription parser. Unknown event strings are normalized to `*`,
not rejected. The SQL apply function maps WAL record types `I`, `U`, and `D`;
no `TRUNCATE` subscription path was found.

Sources: `lib/extensions/postgres_cdc_rls/subscriptions.ex:377`,
`lib/realtime/tenants/repo/migrations/20260626120000_readd_postgrest_filter_ops.ex:290`.

**Assumption H5.** For `UPDATE`, the server sends both `old_record` and
`record`. For `DELETE`, only `old_record`. For `INSERT`, only `record`.
(§5.3 `InsertAction`/`UpdateAction`/`DeleteAction`)

- Confirmed? Is `old_record` always populated on UPDATE, or only when
  `REPLICA IDENTITY FULL` is set on the table?
- If `REPLICA IDENTITY` is not `FULL`, what's returned for DELETE? (Just
  PKs, or entire row?)
- Schema column order and types match what PostgREST returns for selects?

**Finding.** Confirmed at the field-shape level: INSERT has `record`, UPDATE
has `record` and `old_record`, DELETE has `old_record`. Contents of
`old_record` depend on what WAL supplies and on RLS. The latest SQL limits
DELETE `old_record` under RLS to primary-key columns; without full replica
identity, old values are not guaranteed to be the full row. Column/type payloads
come from the Realtime CDC SQL output, not directly from PostgREST.

Sources: `lib/extensions/postgres_cdc_rls/replication_poller.ex:474`,
`lib/extensions/postgres_cdc_rls/replication_poller.ex:499`,
`lib/extensions/postgres_cdc_rls/replication_poller.ex:525`,
`lib/extensions/postgres_cdc_rls/replications.ex:87`,
`lib/realtime/tenants/repo/migrations/20260626120000_readd_postgrest_filter_ops.ex:563`,
`lib/realtime/tenants/repo/migrations/20260626120000_readd_postgrest_filter_ops.ex:590`.

**Assumption H6.** If the underlying publication doesn't include a table
or column, events silently don't fire - no error at join time. (§5.3)

- Confirmed? Or does the server reject the join with an error if the
  table/column doesn't exist in `supabase_realtime` publication?

**Finding.** False. The channel join may initially succeed, but Postgres
subscription setup reports errors through `"system"` messages with extension
`"postgres_changes"` when subscription params are malformed, the table is not
in the publication, the table does not exist, columns are invalid, or values
cannot be cast. This is not a silent no-events case.

Sources: `lib/realtime_web/channels/realtime_channel.ex:352`,
`lib/realtime_web/channels/realtime_channel.ex:379`,
`lib/extensions/postgres_cdc_rls/cdc_rls.ex:95`,
`lib/extensions/postgres_cdc_rls/subscriptions.ex:60`,
`test/realtime/extensions/cdc_rls/subscriptions_test.exs:458`,
`test/realtime/extensions/cdc_rls/subscriptions_test.exs:797`,
`test/realtime/extensions/cdc_rls/subscriptions_test.exs:1229`.

**Assumption H7.** Postgres change subscriptions are automatically
re-registered on rejoin - the client just re-sends the same join config.
(§9.2 "postgres change subscriptions are restored")

- Confirmed? Any gaps during rejoin that could lose events? If so, is
  there a replay/cursor mechanism like broadcast replay?

**Finding.** Confirmed for rejoin behavior: the client re-sends join config and
the server creates fresh CDC subscriptions. No Postgres change replay/cursor
mechanism was found, so disconnect/rejoin gaps are possible. Broadcast replay
does not cover Postgres changes.

Sources: `lib/realtime_web/channels/realtime_channel.ex:819`,
`lib/realtime_web/channels/realtime_channel.ex:856`,
`lib/extensions/postgres_cdc_rls/cdc_rls.ex:31`,
`lib/realtime/messages.ex:13`.

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

**Finding.** Event name and payload shape are confirmed, but the ACK assumption
is false. `access_token` is a per-channel event and successful/ignored updates
return `noreply`, not `phx_reply`. New valid tokens rebuild authorization
context, policies, and Postgres-change claims; revoked read permission or
invalid/expired/malformed tokens produce a `"system"` error and channel stop.
Tokens starting with `sb_`, nil tokens, and identical tokens are ignored.

Sources: `lib/realtime_web/channels/realtime_channel.ex:520`,
`lib/realtime_web/channels/realtime_channel.ex:524`,
`lib/realtime_web/channels/realtime_channel.ex:534`,
`lib/realtime_web/channels/realtime_channel.ex:572`,
`test/integration/rt_channel/token_handling_test.exs:182`,
`test/integration/rt_channel/token_handling_test.exs:295`.

**Assumption I2.** On `token_expired`, the server sends a message the
client can distinguish from other errors, and the operation that triggered
it fails with a retryable error. (§6.3 "Reactive path")

- What's the exact wire signal - a `phx_error` with `reason: "token_expired"`?
  On which channel / on the socket itself?
- Does `token_expired` close the socket, close the individual channel, or
  just reject the in-flight push?
- After pushing a refreshed token, is the retry on the same original
  request, or do we need to resubscribe?

**Finding.** No dedicated `token_expired` wire event was found. Expiry is
validated periodically and on token update/join. When detected on an existing
channel, the server pushes a `"system"` error message and stops the channel,
which leads to `phx_close`; join-time expiry returns a `phx_reply` error reason
such as `InvalidJWTToken: Token has expired`. The client should treat this as a
channel resubscribe path after refresh, not as a retry of the original push on
the same channel.

Sources: `lib/realtime_web/channels/realtime_channel.ex:412`,
`lib/realtime_web/channels/realtime_channel.ex:746`,
`lib/realtime_web/channels/realtime_channel.ex:776`,
`lib/realtime_web/channels/realtime_channel.ex:787`,
`test/integration/rt_channel/token_handling_test.exs:230`,
`test/integration/rt_channel/token_handling_test.exs:338`,
`test/integration/rt_channel/token_handling_test.exs:366`.

**Assumption I3.** JWT `exp` is not parsed or enforced client-side - the
SDK reacts only to server-sent `token_expired`. (Decision 9 "No JWT
parsing in the SDK")

- Is this safe, or is there meaningful latency between local expiry and
  server detection that would justify proactive rotation?

**Finding.** Server-side enforcement is real and periodic. The server parses
`exp`, schedules the next check at the lesser of five minutes or time until
expiry, and closes the channel on expiry. Client-side proactive parsing is not
required for correctness, but it could avoid server-initiated channel close
latency.

Sources: `lib/realtime_web/channels/realtime_channel.ex:746`,
`lib/realtime_web/channels/realtime_channel.ex:759`,
`test/integration/rt_channel/token_handling_test.exs:338`.

---

## 10. Error Taxonomy

**Assumption J1.** All server-sent errors arrive as `phx_error` /
`phx_reply {status: "error"}` with a `reason: String` field. No structured
error codes. (§7 RealtimeError)

- Is there a stable set of `reason` strings we can pattern-match to map
  into our error cases? Example: `"unauthorized"`, `"rate_limited"`,
  `"token_expired"`, `"server_error"`, etc.
- If the set is unstable: can we get a structured `code` field added?

**Finding.** False as a universal statement. Wire errors are mixed: join
failures use `phx_reply` with an error reason; runtime channel failures often
use a `"system"` event with fields `extension`, `status`, `message`, and
`channel`; HTTP errors use controller/fallback JSON or empty responses. The
backend has an `ERROR_CODES.md` operational-code list, but those codes are not
consistently present as structured WebSocket payload fields.

Sources: `lib/realtime_web/channels/realtime_channel.ex:787`,
`lib/realtime_web/channels/realtime_channel.ex:352`,
`lib/realtime_web/channels/realtime_channel.ex:776`,
`lib/realtime_web/controllers/broadcast_controller.ex:14`,
`ERROR_CODES.md:1`.

**Assumption J2.** Server close codes on unexpected socket close are
meaningful and distinct for auth vs transient vs policy violations.

- What close codes does the server use, and for which scenarios?
  (E.g., 4001 = auth, 4003 = rate limit, 4008 = policy, etc.)
- Any close code that means "do not reconnect" vs "reconnect with backoff"?

**Finding.** Not confirmed. No custom Realtime WebSocket close-code taxonomy was
found. Channel shutdown is usually represented by `phx_close` after a system
message or by transport process termination for certain rate-limit/no-channel
cases. Connect failures surface through HTTP/WebSocket handshake rejection
rather than documented custom close codes.

Sources: `lib/realtime_web/channels/realtime_channel.ex:776`,
`lib/realtime_web/channels/realtime_channel.ex:195`,
`lib/realtime_web/channels/realtime_channel/tracker.ex:73`,
`lib/realtime_web/channels/user_socket.ex:149`.

---

## 11. Rate Limits and Quotas

**Assumption K1.** Rate limits exist but are not surfaced in the v3 API
except via `.rateLimited(retryAfter:)`. (§7)

- What are the default server-side limits - messages/sec per channel,
  connections per project, topics per socket, presence entries per
  channel, presence state size?
- When exceeded via WS: what's the wire signal? A `phx_error` with
  `reason: "rate_limited"` + a `retry_after` field? Connection close?
- When exceeded via HTTP: `429` with `Retry-After` header?

**Finding.** Rate limits are tenant/project-level counters, not uniformly
per-channel. Defaults include `max_events_per_second = 100`,
`max_joins_per_second = 100`, `max_channels_per_client = 100`,
`max_concurrent_users = 200`, `max_presence_events_per_second = 1000`, and
per-client presence update limit `5` calls per `30_000` ms. WS rate-limit
signals are not a structured retry-after field: message/presence limits push
`"system"` errors and stop or reject; join-rate limit sends a transport
disconnect path; channel-limit join returns an error reason. HTTP returns `429`
with `x-rate-*` headers and no `Retry-After`.

Sources: `config/runtime.exs:97`, `config/runtime.exs:98`,
`config/runtime.exs:99`, `config/runtime.exs:100`,
`config/runtime.exs:101`, `config/runtime.exs:13`,
`lib/realtime/api/tenant.ex:22`,
`lib/realtime_web/channels/realtime_channel.ex:188`,
`lib/realtime_web/channels/realtime_channel.ex:298`,
`lib/realtime_web/channels/realtime_channel.ex:476`,
`lib/realtime_web/plugs/rate_limiter.ex:29`.

**Assumption K2.** There's no per-client connection cooldown - clients
can reconnect immediately after any close. (§9.1 ReconnectionPolicy)

- Is there a server-side "too many reconnects" throttle? If so, what
  delays does it enforce and how are they communicated?

**Finding.** No explicit per-client reconnect cooldown was found. There are
tenant connection/user, join-rate, and message-rate limits, plus a
`connect_error_backoff_ms` sleep before returning some connect errors. Clients
can still be rejected by those limits when reconnecting aggressively.

Sources: `lib/realtime_web/channels/user_socket.ex:149`,
`lib/realtime_web/channels/realtime_channel.ex:634`,
`lib/realtime_web/channels/realtime_channel.ex:672`,
`config/runtime.exs:99`,
`config/runtime.exs:101`.

---

## 12. Ordering and Delivery

**Assumption L1.** Within a single topic, for a single client, events
arrive in the order the server processed them. Across topics, no ordering
guarantee. (Implicit throughout)

- Confirmed per-topic-per-client ordering?
- For postgres_changes specifically: does the server guarantee WAL order
  within a table, or can concurrent transactions reorder?

**Finding.** Cross-topic ordering should not be assumed. Per-topic ordering is
not documented as an explicit backend contract, but same-process dispatch is
sequential through Phoenix PubSub/fastlane. Postgres changes come from logical
replication polling and are dispatched from the poller output; the code does
not expose a client cursor or documented ordering guarantee beyond WAL-derived
processing.

Sources: `lib/realtime_web/channels/realtime_channel/message_dispatcher.ex:70`,
`lib/extensions/postgres_cdc_rls/replication_poller.ex:379`,
`lib/extensions/postgres_cdc_rls/replications.ex:87`.

**Assumption L2.** Broadcasts and postgres_changes on the same topic
interleave arbitrarily. (§3, §5)

- Confirmed? No implicit ordering between them?

**Finding.** Confirmed. Broadcasts and Postgres changes use different producer
paths and no ordering coordination between those paths was found.

Sources: `lib/realtime_web/channels/realtime_channel/broadcast_handler.ex:120`,
`lib/extensions/postgres_cdc_rls/replication_poller.ex:379`,
`lib/realtime_web/channels/realtime_channel/message_dispatcher.ex:70`.

**Assumption L3.** Presence `diff` events and broadcast events on the
same topic interleave arbitrarily.

- Confirmed?

**Finding.** Confirmed. Presence and broadcast are separate event paths over the
same channel topic; no ordering coordination was found.

Sources: `lib/realtime_web/channels/realtime_channel/presence_handler.ex:193`,
`lib/realtime_web/channels/realtime_channel/broadcast_handler.ex:120`,
`lib/realtime_web/channels/realtime_channel/message_dispatcher.ex:70`.

---

## 13. Reconnection / Resilience

**Assumption M1.** After a client reconnect, the server has no memory of
prior subscriptions - the client must re-send all `phx_join`s. (§9.2)

- Confirmed, no session resumption?
- If session resumption is coming in a future version, is there a
  protocol hint we should leave room for?

**Finding.** Confirmed. Channels, presence, and Postgres subscriptions are tied
to socket/channel processes. No session-resumption protocol or reconnect token
was found.

Sources: `lib/realtime_web/channels/realtime_channel.ex:43`,
`lib/realtime_web/channels/realtime_channel.ex:617`,
`lib/realtime_web/channels/realtime_channel/presence_handler.ex:158`,
`lib/extensions/postgres_cdc_rls/subscription_manager.ex:189`.

**Assumption M2.** The server does not emit a "you missed events while
disconnected" signal. Gaps are silent and the client cannot detect them
without broadcast replay. (§3.1 "Gaps are inherent")

- Confirmed no gap-detection mechanism?

**Finding.** Confirmed for a general gap signal. No missed-events signal was
found. Broadcast replay can recover retained private broadcast messages if the
client requests it at join. Postgres changes have no replay/cursor, and the
replication poller can skip real rows when rate limits are triggered.

Sources: `lib/realtime/messages.ex:13`,
`lib/realtime_web/channels/realtime_channel.ex:966`,
`lib/extensions/postgres_cdc_rls/replication_poller.ex:404`,
`lib/extensions/postgres_cdc_rls/replication_poller.ex:437`.

---

## 14. App Lifecycle

**Assumption N1.** The WebSocket can survive short iOS/macOS
background-foreground transitions without the server terminating the
connection. (§9.3 handleAppLifecycle)

- What's the server-side idle/heartbeat timeout that determines how long
  a backgrounded app can stay connected before the server closes?
- Is there a way to "pause" a connection server-side without closing it?
  (Probably not, but worth asking.)

**Finding.** Not confirmed from Realtime code. No server-side pause mechanism
was found. The endpoint does not set a Realtime-specific WebSocket heartbeat
timeout; lifecycle survival depends on Phoenix/Cowboy defaults, client
heartbeat behavior, and deployment/LB idle timeouts. Empty sockets can be
killed by the no-channel tracker after the configured interval.

Sources: `lib/realtime_web/endpoint.ex:16`, `config/runtime.exs:80`,
`lib/realtime_web/channels/realtime_channel/tracker.ex:73`.

---

## 15. Protocol Limits (Hard Numbers We Want to Document)

Backend-derived values from the local checkout:

| Limit | Backend finding | Source |
| ----- | --------------- | ------ |
| Max topics per WebSocket | Tenant `max_channels_per_client`, default 100. | `config/runtime.exs:98`; `lib/realtime_web/channels/realtime_channel.ex:653` |
| Max concurrent WebSockets per project | Tenant `max_concurrent_users`, default 200. Endpoint HTTP max connections default is 1000. | `config/runtime.exs:99`; `config/runtime.exs:426`; `lib/realtime_web/channels/realtime_channel.ex:672` |
| Max broadcast payload size (JSON) | Tenant `max_payload_size_in_kb`, default 3000 KB, checked with `:erlang.external_size(payload) <= max * 1000 + 500`; WebSocket frame cap is 5,000,000 bytes. | `lib/realtime/api/tenant.ex:23`; `lib/realtime/tenants.ex:532`; `lib/realtime_web/endpoint.ex:20` |
| Max broadcast payload size (binary) | Same tenant payload-size rule for WS and HTTP single binary; WebSocket frame cap still applies. | `lib/realtime/tenants/single_broadcast.ex:120`; `lib/realtime/tenants.ex:532`; `lib/realtime_web/endpoint.ex:20` |
| Max presence metas per key | No hard per-key count found. Same socket/key updates one meta; multiple sockets may share a key. | `lib/realtime_web/channels/realtime_channel/presence_handler.ex:141`; `lib/realtime_web/channels/realtime_channel/presence_handler.ex:162` |
| Max presence state bytes per channel | No channel-wide state byte cap found. Individual track payloads use the tenant payload-size check; presence event rate limits apply. | `lib/realtime/tenants.ex:532`; `lib/realtime_web/channels/realtime_channel/presence_handler.ex:202` |
| Max `postgres_changes` entries per join | No explicit per-join count found; bounded indirectly by join payload/frame size and resource limits. | `lib/realtime_web/channels/payloads/config.ex:13`; `lib/realtime_web/channels/realtime_channel.ex:819` |
| Max `in` list length in filter | 100 values. | `lib/realtime/tenants/repo/migrations/20260527120000_add_select_columns_to_subscriptions.ex:75` |
| Broadcast replay retention window | Message partition cleanup deletes partitions older than about 72 hours. | `lib/realtime/messages.ex:69` |
| Broadcast replay max limit | Default 25, hard max 25, min 1. | `lib/realtime/messages.ex:10`; `lib/realtime/messages.ex:22`; `lib/realtime_web/channels/realtime_channel.ex:974` |
| Default heartbeat timeout (server side) | No Realtime-specific value found in endpoint config; relies on Phoenix/Cowboy/deployment behavior. | `lib/realtime_web/endpoint.ex:16` |
| Rate limit: broadcasts/sec per channel | Tenant events/sec limit, default 100; this is tenant/project-level accounting rather than per-channel only. | `config/runtime.exs:100`; `lib/realtime_web/channels/realtime_channel.ex:298`; `lib/realtime/tenants/single_broadcast.ex:211` |
| Rate limit: joins/sec per socket | Tenant joins/sec limit, default 100. | `config/runtime.exs:101`; `lib/realtime_web/channels/realtime_channel.ex:634` |

---

## 16. Open Design Questions that Depend on Backend

These are v3 API decisions we deliberately deferred - the answer from
backend may change our preference.

1. **Unbounded broadcast buffers.** We picked unbounded per-consumer
   buffers (§3.1, Decision 7). Backend code does not show a durable
   per-subscriber queue or client backpressure contract. It does enforce
   WebSocket max frame size, heap/process limits, and tenant rate counters, so
   the Swift SDK should still define its own consumer buffering/drop policy.
2. **Automatic retry on `token_expired`.** We retry once (§6.3, Decision 10).
   Backend token rotation is per-channel and successful `access_token` updates
   are not ACKed. Expired or invalid tokens close the channel after a system
   error, so retry should mean refresh + resubscribe rather than replaying the
   original push on the same channel.
3. **HTTP broadcast batching.** We expose a batch form (§3.3). Backend batch
   and single endpoints have materially different private-topic failure
   semantics: single private unauthorized returns forbidden, while batch private
   unauthorized messages can be skipped while the request still returns 202.
   Batch also checks the requested batch size against the tenant events/sec
   limit before sending.
4. **Presence key ownership.** We pushed presence key to channel-level
   config (§4, Decision 17). Backend confirms channel-level key ownership:
   same socket/key has a single updatable meta, and generated keys are
   per-join UUIDs. Per-track presence keys would require a different backend
   wire contract.

---

## How to respond

Ideal format: for each question, either "yes, confirmed", "no, here's the
actual behavior", or "undefined - please don't rely on it". For the
numeric limits table, fill in concrete numbers or "no hard limit".
