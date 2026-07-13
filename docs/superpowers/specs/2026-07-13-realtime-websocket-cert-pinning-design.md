# Realtime WebSocket Certificate Pinning — Design

## Motivation

`URLSessionWebSocket` (Realtime's WS transport) always builds its own internal
`URLSession` and assigns it a private `_Delegate`. Any `URLSessionDelegate` an
app configures for certificate pinning on its main Supabase session (Auth,
PostgREST, Storage) never reaches the Realtime WebSocket connection — it
silently connects unpinned. There is currently no hook to evaluate server
trust on the Realtime WS session.

Reference: [PR #1117](https://github.com/supabase/supabase-swift/pull/1117)
proposed a narrow `serverTrustHandler` closure on `RealtimeClientOptions` to
close this gap. This spec proposes a more general fix that reuses the SDK's
existing session-injection idiom instead of adding a single-purpose closure,
so the same mechanism can serve future delegate needs without another
breaking/additive API each time.

## Goals

- Let apps pin the Realtime WebSocket connection using the same
  `URLSessionDelegate` they already use for Auth/PostgREST/Storage.
- No new API concept: reuse the `session: URLSession` idiom already present
  on `StorageHTTPSession` and `SupabaseClientOptions.global.session`.
- Apps using the `SupabaseClient` facade that already pin `global.session`
  get Realtime pinning for free — no extra config.
- Fully additive; no breaking changes to `RealtimeClientOptions` or
  `RealtimeClientV2`.

## Non-goals

- Do not build a generic, arbitrary delegate-method forwarding system.
  Only the authentication-challenge path is forwarded; WebSocket lifecycle
  delegate methods (open/close/complete) stay owned by Realtime internally.
- Do not change how Storage/Auth/PostgREST pinning works today.
- No behavior change for apps that don't configure a session/delegate.

## Design

### Key mechanism

Since iOS 15 / macOS 13 (below this package's minimum targets, so always
available on Apple platforms), `URLSessionTask` exposes a per-task
`delegate: URLSessionTaskDelegate?`. When a task-level delegate implements a
method, it's called instead of the session-level delegate; when it doesn't
implement a given method, the session's own delegate is called as a
fallback. This means Realtime does not need to take ownership of, or merge
with, the caller's `URLSession` — it only needs to sit in front of whatever
delegate that session already has, for the one method that matters
(`urlSession(_:task:didReceive:completionHandler:)`), while continuing to own
the WebSocket lifecycle methods on the same per-task delegate object.

### API surface

- `RealtimeClientOptions` gains a new public property/init parameter:
  `session: URLSession = .shared`. Same name, same default, same mental
  model as `StorageHTTPSession(session:)` and `SupabaseClientOptions.global.session`.
  Added the same way `vsn` was added previously (new parameter on the
  primary initializer with a default value; existing call sites unaffected).
- `SupabaseClient.swift` passes `configuration.global.session` into the
  `RealtimeClientOptions` it builds internally for the facade. This is
  currently not wired at all — that's the actual gap for facade users.
- Standalone `RealtimeClientV2` users pass their own preconfigured `session:`
  the same way they would to Storage.

### Internal changes

- `URLSessionWebSocket.connect(to:protocols:headers:session:)` replaces the
  `configuration: URLSessionConfiguration?` parameter with a `session:
  URLSession` parameter (defaulting to `.shared` at the call site in
  `RealtimeClientV2` when no session is configured). The WS task is created
  via `session.webSocketTask(with:)` instead of building a fresh session.
- The task's `delegate` is set to Realtime's internal `_Delegate`.
- `_Delegate` captures `session.delegate` at connect time (as `(any
  URLSessionDelegate)?`) and adds:
  ```swift
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    if let wrapped = wrappedDelegate as? URLSessionTaskDelegate {
      wrapped.urlSession?(session, task: task, didReceive: challenge, completionHandler: completionHandler)
    } else {
      completionHandler(.performDefaultHandling, nil)
    }
  }
  ```
- All existing `_Delegate` methods (`didCompleteWithError`,
  `didOpenWithProtocol`, `didCloseWith`) are unchanged.
- The captured `wrappedDelegate` reference is not `Sendable` in general
  (`URLSessionDelegate` conformers are typically `NSObject` subclasses with
  no `Sendable` guarantee). It's called only from the delegate queue, the
  same way `URLSession` itself would call it. `_Delegate` already stores
  mutable non-`Sendable`-safe state via `LockIsolated` (from
  `ConcurrencyExtras`, already a dependency of this file) — wrap
  `wrappedDelegate` in `LockIsolated` the same way.

### Platform risk

`URLSessionTask.delegate` may not exist in swift-corelibs-foundation
(Linux). Linux is build-only for this package, not production-supported
(per `AGENTS.md`). Guard the task-delegate assignment with `#if
canImport(FoundationNetworking)` / `#else`, matching the file's existing
conditional-compilation pattern — on Linux, fall back to today's behavior
(no pinning hook, `_Delegate` stays the session-level delegate as it is now).

### Testing

- A fake `URLSession` (real `URLSession` instance with a test
  `URLSessionTaskDelegate` implementing
  `urlSession(_:task:didReceive:completionHandler:)`) is passed via
  `RealtimeClientOptions(session:)` — assert the test delegate's method is
  invoked during connect.
- A `URLSession` with no delegate (`.shared` or a session with `delegate:
  nil`) — assert default handling occurs (no crash, connection proceeds).
- `SupabaseClient.swift` wiring: assert `configuration.global.session` is
  the session passed into the constructed `RealtimeClientOptions`.

## Compatibility

Fully additive. `RealtimeClientOptions.session` defaults to `.shared`;
apps that don't set it see no behavior change. `URLSessionWebSocket` is an
internal (non-`public`) type — its `connect` signature change
(`configuration` → `session`) carries no public-API compatibility burden.

**Addendum (found during implementation):** `connect` must not use a
`.shared`-valued `session` parameter directly for the WebSocket task — doing
so would route the connection through process-wide `URLSession` state (e.g.
another part of the same process registering a global `URLProtocol` for
mocking or interception), which the pre-existing implementation was immune
to by always building its own dedicated session. `connect` treats `session
=== URLSession.shared` as "no session was explicitly supplied" and keeps
building a dedicated internal session in that case; it only uses the
caller's session directly (enabling pinning) when it's a distinct instance.
This preserves prior behavior for the common case and keeps pinning strictly
opt-in.
