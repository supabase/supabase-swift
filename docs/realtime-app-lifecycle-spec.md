# Realtime App Lifecycle Handling — Cross-Platform Specification

Status: implemented in `supabase-swift` (PR #967). This document describes the
intended behavior so it can be ported to other Supabase client libraries
(`supabase-js`, `supabase-flutter`, `supabase-kt`, `supabase-py`, etc.) with
consistent semantics.

## 1. Problem

On mobile and desktop platforms, an app's WebSocket connection can be
torn down by the OS while the process is backgrounded (screen off, app
swiped away from foreground, device suspended). When the user returns to
the app, the Realtime client is left in a stale state:

- The socket may be half-open or fully closed.
- Existing channel subscriptions are no longer receiving messages.
- The library previously required the app developer to manually detect
  foregrounding and call `connect()` / re-subscribe.

The goal of this feature is to recover automatically: when the app
returns to the foreground, if the socket is not connected, reconnect and
re-join every channel that was previously subscribed — without the user
noticing.

## 2. Goals

- **Self-healing**: foreground → reconnect → re-join, with no app code.
- **Zero churn on fast transitions**: brief background/foreground
  toggles must not trigger a disconnect/reconnect cycle when the OS left
  the socket alive.
- **Only recover what was there**: if the socket was *not* connected at
  the moment the app backgrounded, foregrounding must not spontaneously
  open a connection. The feature repairs existing sessions; it does
  not start new ones.
- **Opt-out, not opt-in**: default on for platforms where it is safe and
  meaningful; off everywhere else.
- **Non-invasive**: no new state machine in the client; feature composes
  on top of the existing `connect()` and channel-rejoin paths.

## 3. Non-goals

- Do **not** proactively disconnect when the app backgrounds. The OS
  may keep the connection alive for a while; tearing it down ourselves
  wastes work and produces visible "Disconnected → Connected" flicker
  for users who only briefly switch apps.
- Do **not** expose a public `setAppStateActive(isActive:)` or similar
  toggle. App developers shouldn't have to plumb lifecycle events into
  the SDK manually.
- Do **not** try to detect network loss or sleep/wake at the OS level —
  that is a separate problem handled by the existing reconnect loop.
- Do **not** attempt lifecycle observation on platforms without a
  well-defined "foreground" event (servers, headless runtimes, CLIs,
  Linux desktop without a DE contract).

## 4. Public API

Each platform SDK exposes a single boolean option on the Realtime client
configuration:

```
handleAppLifecycle: Bool   (Swift / Kotlin)
handleAppLifecycle: bool   (Dart / Python)
handleAppLifecycle: boolean (TypeScript)
```

Defaults:

| Platform        | Default |
|-----------------|---------|
| iOS             | `true`  |
| macOS           | `true`  |
| tvOS            | `true`  |
| visionOS        | `true`  |
| Android         | `true`  |
| Flutter (mobile)| `true`  |
| Browser (web)   | `true`  (use `visibilitychange`) |
| Node.js         | `false` |
| watchOS / Linux / server runtimes | `false` |

When set to `false`, the SDK performs no lifecycle observation and the
app is responsible for calling `connect()` (and letting channels
re-subscribe) itself if desired.

## 5. Behavior

### 5.1 Observation

When `handleAppLifecycle == true`, the Realtime client installs a
platform-appropriate observer that fires on the equivalents of
**"app will become active / foreground"** *and* **"app did enter
background / resign active"**:

| Platform | Foreground signal | Background signal |
|----------|-------------------|-------------------|
| iOS / tvOS / visionOS | `UIApplication.willEnterForegroundNotification` | `UIApplication.didEnterBackgroundNotification` |
| macOS                 | `NSApplication.willBecomeActiveNotification`    | `NSApplication.didResignActiveNotification` |
| Android               | `ProcessLifecycleOwner` → `Lifecycle.Event.ON_START` | `Lifecycle.Event.ON_STOP` |
| Browser               | `visibilitychange` → `visible`                  | `visibilitychange` → `hidden` |
| Flutter               | `AppLifecycleState.resumed`                     | `AppLifecycleState.paused` |

The SDK still does **not** proactively disconnect on the background
signal. The background observer exists only to record a single flag
(see below).

### 5.2 On background

When the background signal fires, the client records whether the
socket is connected at that moment:

```
fn handleAppBackground():
    wasConnectedBeforeBackground = (status == .connected)
```

Nothing else happens — the socket is left alone.

### 5.3 On foreground

When the foreground signal fires, the client runs:

```
async fn handleAppForeground():
    let wasConnected = wasConnectedBeforeBackground
    wasConnectedBeforeBackground = false          # reset for next cycle

    if not wasConnected:
        return                                    # never had a connection; do nothing

    if status == .connected:
        return                                    # socket survived, nothing to do

    let hadChannels = channels.isNotEmpty
    await connect()

    if hadChannels and status == .connected:
        await rejoinChannels()
```

Notes:

- The **"was connected before background"** guard is the critical
  behavior change: foregrounding an idle client (one the developer
  never called `connect()` on, or that was deliberately disconnected
  while backgrounded) does **not** open a new connection. The feature
  only repairs sessions that existed at the moment of backgrounding.
- The `status != .connected` guard keeps brief background cycles
  zero-cost when the OS did not kill the socket.
- The flag is reset on every foreground transition, so a subsequent
  background → foreground cycle re-evaluates the current state from
  scratch.
- `rejoinChannels()` re-sends `phx_join` for every channel already
  registered with the client. Channels keep their configuration
  (postgres filters, presence, broadcast subscriptions) across the
  reconnect — it is a logical re-subscribe, not a new one.
- If the socket cannot reconnect (e.g. no network), `connect()` returns
  in whatever error state the normal reconnect flow produces; the
  foreground handler does not add its own retry loop. The existing
  reconnect backoff is the single source of truth for retries.
- If the foreground signal fires without a prior background signal
  (e.g. the very first launch, or a platform that emits extra
  foreground events), the flag defaults to `false` and the handler
  no-ops — safe by construction.

### 5.4 Lifecycle manager lifetime

The observer is owned by the Realtime client. It is:

- created lazily when the client is initialized with
  `handleAppLifecycle == true`;
- torn down when the client is deinitialized / disposed;
- **not** recreated or reconfigured at runtime — the option is
  immutable after client construction.

The observer must hold only a **weak** reference to the client, so that
the lifecycle manager never extends the client's lifetime.

## 6. Platform-specific integration notes

### 6.1 iOS / macOS / tvOS / visionOS (reference implementation)

- Uses `NotificationCenter.default.addObserver(forName:)` for both
  foreground (`willEnterForegroundNotification` /
  `willBecomeActiveNotification`) and background
  (`didEnterBackgroundNotification` / `didResignActiveNotification`).
- The background handler writes a single flag under a lock and does
  not touch the socket.
- The foreground handler hops to the actor
  (`Task { await client.handleAppForeground() }`) because notification
  callbacks run on arbitrary threads.

### 6.2 Android / Kotlin

- Use AndroidX `ProcessLifecycleOwner.get().lifecycle.addObserver(...)`.
- Trigger on `Lifecycle.Event.ON_START` (app is foreground-visible).
- `ON_STOP` is **ignored** — same rationale as iOS.
- Run `handleAppForeground` on the client's coroutine scope
  (`Dispatchers.Default` or the SDK's own).

### 6.3 Flutter

- Implement `WidgetsBindingObserver` and register with
  `WidgetsBinding.instance.addObserver(this)`.
- Trigger on `didChangeAppLifecycleState(AppLifecycleState.resumed)`.
- On platforms where `WidgetsBinding` is unavailable (pure-Dart CLI),
  default `handleAppLifecycle` to `false`.

### 6.4 Browser (supabase-js)

- Listen on `document.addEventListener('visibilitychange', …)`.
- Trigger when `document.visibilityState === 'visible'` after a prior
  transition to `'hidden'`.
- Optionally also listen on `window.addEventListener('focus', …)` —
  both are fine; pick whichever gives a cleaner signal in testing.
- Default `true` in browser bundles, `false` in Node.js bundles.

### 6.5 Node.js / server

- No lifecycle concept applies; default `handleAppLifecycle = false`.
- The option should still exist in the type so code is portable between
  browser and server bundles without conditionals.

## 7. Concurrency and thread-safety

- Foreground callbacks may fire on any thread/queue. The client must
  marshal the foreground handler onto its own executor/isolate before
  touching internal state (channel registry, connection status).
- Multiple foreground signals may arrive in quick succession (e.g. a
  modal dismissal on iOS). `handleAppForeground` is idempotent: it is
  a no-op once `status == .connected`.
- A foreground signal arriving mid-`connect()` must not kick off a
  parallel connect. Each platform should ensure single-flight behavior,
  either because `connect()` itself is idempotent or by guarding with a
  "connecting" state.

## 8. Interaction with other options

- `connectOnSubscribe` (auto-connect on first `channel.subscribe()`):
  unchanged. If the app has no channels yet and comes to the
  foreground, `handleAppForeground` will still call `connect()` to
  restore the socket — but `rejoinChannels()` is skipped because there
  is nothing to re-join.
- `disconnectOnSessionLoss`: unchanged. Auth-driven disconnects are
  independent of lifecycle.
- `reconnectDelay` / `maxRetryAttempts`: unchanged. The foreground
  handler delegates all retry policy to the existing reconnect loop.

## 9. Observability

Lifecycle-driven transitions surface through the **existing** status
streams. Clients should not emit a new "lifecycle" event type.

- Socket transitions: `statusChange` emits `connecting → connected` (or
  an error state) just as it does for any manual `connect()`.
- Channel transitions: each rejoined channel emits
  `subscribing → subscribed` on its own `statusChange` stream.

This keeps app-side UI logic platform-independent — observing the
status streams is enough to render "reconnecting…" indicators.

## 10. Testing

Each platform SDK should cover, at minimum:

1. **Foreground while connected is a no-op.**
   Subscribe, drive to connected, invoke background then foreground
   handlers, assert no status change and no new `phx_join` frames.

2. **Foreground without a prior background is a no-op.**
   Construct a client, do not connect, invoke the foreground handler
   directly, assert status remains `disconnected`.

3. **Foreground does not reconnect if the socket was not connected at
   background time.**
   Construct a client, do not connect, invoke background then
   foreground handlers, assert status remains `disconnected`.

4. **Foreground reconnects when the socket was connected at background
   time and has since been torn down.**
   Connect the client, invoke the background handler, simulate a
   socket close (e.g. manual `disconnect()`), invoke the foreground
   handler, assert status reaches `connected`.

5. **Foreground re-joins previously subscribed channels when the
   socket was connected at background time.**
   Subscribe channel A, invoke the background handler, simulate a
   socket close, invoke the foreground handler, assert channel A
   re-subscribes without app code.

6. **`handleAppLifecycle = false` installs no observer.**
   Construct with the option off; assert no lifecycle observer/object
   is created (check internal state directly).

7. **`handleAppLifecycle = true` installs an observer on supported
   platforms.**
   Construct with the option on; assert the observer is present and is
   torn down on client dispose.

Integration / manual test: each SDK should ship a sample app screen
that shows live socket + channel status and a transcript of events, so
a human can background → foreground the app and visually confirm
"disconnected → connecting → connected" and "unsubscribed → subscribing
→ subscribed" transitions without touching the UI. The `supabase-swift`
reference is `Examples/Examples/Realtime/AppLifecycleView.swift`.

## 11. Reference implementation pointers (Swift)

- Option:            `Sources/Realtime/Types.swift` → `RealtimeClientOptions.handleAppLifecycle`
- Observer:          `Sources/Realtime/RealtimeLifecycleManager.swift`
- Background hook:   `Sources/Realtime/RealtimeClientV2.swift` → `handleAppBackground()`
- Recovery method:   `Sources/Realtime/RealtimeClientV2.swift` → `handleAppForeground()`
- State flag:        `Sources/Realtime/RealtimeClientV2.swift` → `MutableState.wasConnectedBeforeBackground`
- Manager install:   `Sources/Realtime/RealtimeClientV2.swift` → init, guarded by `#if os(iOS) || os(tvOS) || os(visionOS) || os(macOS)`
- Tests:             `Tests/RealtimeTests/RealtimeLifecycleTests.swift`
- Manual test view:  `Examples/Examples/Realtime/AppLifecycleView.swift`
