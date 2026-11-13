# Reminders: v2 to v3 migration friction log

This log records what was hard, missing, or could be better while the Reminders example moved
from `release/v2` to v3 (`main` at `f4f132a0`). The migration followed `V3_MIGRATION.md` and the
module guides in `docs/migrations/v3/`.

Severity:

- **Gap**: the guide did not say what the app needed. I had to read the SDK source.
- **Friction**: the guide covers it, but it was slow or easy to miss.
- **Idea**: an improvement to the SDK or the guide. Nothing blocked.

## Summary

The migration was small. The first build had 4 errors in 2 files. After the fixes for those and
for the Realtime API, the app built with no warnings. Most of the time went to the "Silent
changes" lists, which is what the guide asks for. Those lists found one real behavior gap in the
app (no reload after a Realtime rejoin).

| Area | Change in the app |
| --- | --- |
| Client | `SupabaseClientOptions` to `try! SupabaseClient(...)`; `emitLocalSessionAsInitialSession` removed |
| Auth | Hand-written `SessionStore` replaced by `AuthModel`; `signUp` result now discarded with `_ =` |
| Storage | `upload(_:data:options: FileOptions)` to `upload(path:data:options: UploadOptions)`; `download(path:)` now needs `.data()` |
| Realtime | `RealtimeChannelV2` to `RealtimeChannel`; `postgresChange(AnyAction.self, ...)` to `await postgresChanges(of:table:)`; `subscribeWithError()` to `subscribe()`; reload on `.resubscribed` |
| PostgREST | `error.code == "23505"` to `.uniqueViolation` |

## Entries

### 1. Gap: what to do with an expired session in `AuthModel`

The v2 app hid an expired stored session behind a spinner until the refresh finished. The Auth
guide says to check `session.isExpired()` in handlers that switch on `.initialSession`. The
`AuthModel` section then tells apps to drop their own wrapper and switch on `auth.status`. But
`AuthStatus.signedIn(Session)` can carry an expired session (the doc comment on the case says so),
for example when the launch refresh failed because the device was offline.

The guide does not say how an `AuthModel` app should handle that case. Should it show the
signed-in UI and let the next request refresh? Or show a spinner? I chose to show the signed-in
UI. The app already shows an offline screen, and the client refreshes before the next request.

**Suggestion**: add one paragraph to "`AuthModel` replaces a hand-written observable wrapper"
about an expired session in `.signedIn`. Or give `AuthModel` a property such as
`isRefreshing` or `needsRefresh`.

### 2. Gap: `.failed` after an automatic rejoin has no recipe

The Realtime guide says: "The automatic rejoin after a reconnect fails the same way, so watch
`statusChanges()` for `.failed` and call `subscribe()` again." It does not say:

- whether `subscribe()` on a `.failed` channel is allowed, or the app must remove the channel
  and make a new one;
- how to stop a loop when the failure is permanent (for example an RLS change);
- how long to wait between attempts.

I did not add this to the app. A naive "on `.failed`, subscribe again" can loop forever. The app
starts the channel again when the network or the scene phase changes, which covers most cases.

**Suggestion**: add a short code sample that handles `.failed` with a bounded retry, or say
which `RealtimeError.Kind` values are worth a retry.

### 3. Friction: reload after `.resubscribed` is not in "Silent changes"

The Realtime guide says, in the "Status enums carry the reason" section, that events sent while a
channel was away are missed, so an app must reload when `events()` emits `.resubscribed`. Every
app that builds state from Postgres changes needs this. The v2 app did not do it, and nothing in
the "Silent changes" list pointed to it. I found it only because I read the whole file.

I added a reload on `.resubscribed` to `DataStore+Realtime.swift`.

**Suggestion**: add a "Silent changes" bullet, or a "Keeping state in sync" section with the
full pattern: open the streams, open `events()`, `subscribe()`, load, then reload on
`.resubscribed`.

### 4. Friction: no SwiftUI environment key, so the guide forces a global client

The Auth guide says "The SDK ships no SwiftUI environment key. Declare one with `@Entry`." An
`@Entry` value needs a default, so the guide's example uses a global
`let supabaseClient = try! SupabaseClient(...)`. The app passed the client down by hand before.
With `AuthModel`, the views that sign in and sign out also need the client, so I followed the
guide and added the global and the `\.supabase` key.

`AuthModel` only observes. It has no `signIn` or `signOut`. So every app that drops its own
wrapper needs some way to reach `client.auth` from a view. Most apps will write the same
`@Entry` code.

**Suggestion**: ship an environment key, or give `AuthModel` access to its client (it holds it
weakly today). At least say in the guide that the sign-in calls move from the wrapper to
`client.auth`.

### 5. Idea: renamed types give "cannot find in scope" with no fix-it

The first build gave:

- `cannot find 'SupabaseClientOptions' in scope`
- `cannot find 'FileOptions' in scope`
- `missing argument label 'path:' in call`
- `cannot convert return expression of type 'DownloadResponse' to return type 'Data'`

Each one sent me to the guide's tables. An `@available(*, unavailable, renamed: "...")` stub for
the most common renames (`SupabaseClientOptions`, `FileOptions`, `RealtimeChannelV2`,
`AnyAction`, `subscribeWithError`, `postgresChange`) would let Xcode offer a fix-it. Swift
allows these stubs at no runtime cost.

### 6. Idea: no named code for `PGRST116`

`PostgrestError.Code` has named members for PostgreSQL codes, such as `.uniqueViolation`. The
app also checks `PGRST116` (`.single()` got 0 rows), which is the most common PostgREST code an
app checks after an optimistic update. The guide's own example compares it to a string literal.
I kept `error.code == "PGRST116"`.

**Suggestion**: add named members for the common `PGRST*` codes, for example `.noRows` or
`.singleObjectNotFound` for `PGRST116`.

### 7. Friction: the Auth guide is long for a common app

`Auth.md` has 1273 lines. This app uses only four Auth APIs: `authStateChanges`, `signIn`,
`signUp`, `signOut`. The changes it needed were in five places in the file (the `isExpired`
property, `emitLocalSessionAsInitialSession`, `authStateChanges`, `AuthModel`, `signUp`). The
"Silent changes" list alone has more than 20 entries, most about Keychain and refresh details
that an email and password app does not touch directly.

**Suggestion**: start `Auth.md` with "If your app only signs in with email and password and
observes the session, read these sections". The same could help `Realtime.md` (about 50 silent
changes, most about presence and broadcast).

### 8. Friction: `signOut()` scope changed, the app must decide

The default `signOut()` scope is now `.local`, not `.global`. The guide says this clearly. It
does not say which one an app like this should use. I kept the new default (`.local`), because
signing out on one phone should not sign the user out on another device.

No change needed in the guide. This entry records the decision.

### 9. Idea: "caller's executor" and an app in Swift 6.0 mode

The overview says SDK `async` functions now run on the caller's executor, and suggests
`@concurrent` for heavy decoding. The app's repositories are `nonisolated` structs, and the app
target builds in Swift 6.0 mode without `NonisolatedNonsendingByDefault`. So their `async`
methods already leave the main actor, and the SDK runs there too. I needed to reason about this
myself.

**Suggestion**: add one sentence: "If your app target does not enable
`NonisolatedNonsendingByDefault`, a `nonisolated async` function of yours still leaves the main
actor, and the SDK runs on the same executor as that function."

### 10. Friction: building `Examples.xcodeproj` alone fails

`xcodebuild -project Examples/Examples.xcodeproj -scheme Reminders` fails with
`Missing package product 'Supabase'`. The package is a local reference that only
`Supabase.xcworkspace` provides. The README says to open the workspace, so this is not a bug,
but the error message gives no hint. This is not a v3 issue.

### 11. Idea: the topic workaround may be obsolete

In v2, a joined channel could not get new streams, and `client.channel` returned the existing
channel for a topic. The app used a new random topic for each start to work around this. In v3,
a stream opened after the join works (the channel joins again), and a removed channel frees its
topic at once. A fixed topic would probably work now. I kept the random topic, because it also
keeps two overlapping starts apart, and the guide does not say that a remove and a new channel
for the same topic in quick succession is safe from races.

### 12. Friction: the `lists` UI flow fails before and after the migration

With Xcode 27 and the iPhone 17 Pro simulator, `maestro/flows/lists.yaml` fails on
`home.list.Groceries is visible`. The app saves the list as `GroceriesI`: an extra "I" gets typed
after `inputText: Groceries`, which follows `inputText: "   "` and `eraseText: 10`. The original
v2 app on `release/v2` fails in the same way, so the migration did not cause it. It looks like a
keyboard input problem in Maestro or the simulator.

Also, `maestro/run.sh` defaults to an `iPhone 18 Pro` simulator, which this Xcode does not have.
I ran it with `SIMULATOR="iPhone 17 Pro"`.

**Suggestion**: make the flow robust, for example with `clearText`-style input or one
`inputText` without the space step, and default `SIMULATOR` to an available device.

## Test results after the migration

- The app builds with no errors and no warnings in the app target.
- Maestro: 9 of 10 flows pass (`attachments`, `auth`, `realtime`, `reminders`, `search`,
  `shared-edits`, `sharing`, `smart-lists`, `update-rollback`). `lists` fails as in entry 12,
  also on v2. In the first full run, `auth`, `shared-edits` and `smart-lists` failed at app
  launch, because the Maestro driver did not start. They pass when run again.
- Not tested: a socket drop that causes a `.resubscribed` reload (entry 3). No flow covers it.

## What worked well

- The "Renames and type changes" tables answered every compile error in seconds.
- `postgresChanges(of:table:)` with `row()` removed the app's own decode helper and the
  `AnyJSON.decoder` call.
- `subscribe()` now waits until the Postgres changes are live. The app's "subscribe, then load"
  order now has the guarantee that the v2 code assumed.
- `catch`-friendly error codes (`.uniqueViolation`) read better than string compares.
- `PostgrestError.message` still holds the server message, so the app's error text needed no
  change.
