# PostgREST v3 Stage 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the internals beneath stage 1's typed surface with value types — a request model,
a public transport seam, a response struct, an error struct, and the filter tree — so that stages 3
and 4 have something to build on and today's builders can be frozen rather than rewritten.

**Architecture:** Standalone types. `PostgrestRequest` is a pure value; `PostgrestSource`,
`PostgrestQuery`, `PostgrestRawQuery` and `PostgrestMutation` are `Sendable` structs over it.
Today's nine files move to `Legacy/` untouched. This resolves the open question spec §4.1 raised —
see [Decisions taken before planning](#decisions-taken-before-planning).

**Tech Stack:** Swift 6.1, SwiftPM, `HTTPTypes` (public dependency), `HTTPRuntime` (internal),
Swift Testing, `HTTPRuntimeTestHelpers`.

**Spec:** [`postgrest-v3.md`](./postgrest-v3.md) — §4.1 (phases), §4.3 (filter tree), §4.7
(transport), §4.8 (response and errors), §4.9 (untyped path), §4.11 (module layout), §4.12
(testing), §6 (migration). Read §4.7 and §4.8 before starting; they carry constraints that are
cheap to honor up front and expensive to retrofit.

---

## Decisions taken before planning

Spec §4.1 and §7 left four things open that this plan needs settled. All four are now decided.

| Question | Decision | Why |
|---|---|---|
| `R` on today's builder, or standalone types? (§4.1) | **Standalone types**, today's nine files moved to `Legacy/` untouched | It is what §4.11's module layout and §6's "behaviorally frozen" both already assume, and it makes stage 4 a labelling exercise rather than surgery. Cost: duplicated request-building for one release, which §6 accepts. |
| How does a caller inject a transport? (§4.7, §7) | **A thin public `PostgrestTransport` in `PostgREST`, expressed over `HTTPTypes`**, bridging to `HTTPRuntime` internally | `HTTPTypes` is already a public dependency of this target. Keeps every `HTTPRuntime` symbol `package`, so `HTTPError` never comes under [ADR 0001](../adr/0001-public-error-types-are-structs.md), and preserves the mocking and timeout capability `FetchHandler` gives callers today. |
| Should an unfiltered `update`/`delete` compile? (§7) | **No.** `.all()` is the explicit opt-out | §7 calls it the most destructive footgun in the API and closing it cheap. There is no migration cost: the typed API is additive and alpha, so nothing depends on today's behavior yet. |
| `PostgrestTyped*` or the spec's names? | **Rename to `PostgrestSource` / `PostgrestQuery` / `PostgrestMutation` in this stage** | The names are unoccupied — the old types are `PostgrestQueryBuilder`, `PostgrestFilterBuilder`, `PostgrestTransformBuilder`. SDK-1519 marks the typed API alpha precisely so this is free, and that window is stages 2–3. |

## Global Constraints

- Swift 6.1 floor, `swift-tools-version:6.1`. Do not raise it.
- **Swift Testing only.** No `XCTest`. Explicit `@Suite`. Test functions drop the `test` prefix.
- Public types in `PostgREST` are prefixed `Postgrest`. Macro attributes stay bare.
- 2-space indentation. `./scripts/format.sh` and `./scripts/spell-check.sh` before every commit.
- Every new public API needs a DocC comment, and carries the alpha warning SDK-1519 introduces.
- Conventional commits. `refactor:` for Task 1, `feat:` for the rest, `feat!:` only where a
  *shipped* symbol changes shape — which in this stage means the renames in Task 7.
- Every commit that adds or renames a public symbol gets a matching `chore(compliance):` commit, the
  pattern the stage 1 PRs established.
- **Nothing in `Legacy/` is edited after Task 1.** If a task needs to change a legacy file, that is a
  signal the boundary is wrong — stop and reconsider rather than editing.

## Three name collisions to know about first

`HTTPRequest` already means three different things in this package:

| Spelling | Module | Access |
|---|---|---|
| `HTTPTypes.HTTPRequest` | swift-http-types | `public` |
| `Helpers.HTTPRequest` | `Sources/Helpers/HTTP/` | `package` |
| `HTTPRuntime.HTTPRequest` | `Sources/HTTPRuntime/` | `package` |

`PostgrestRequestBuilder` currently holds a `Helpers.HTTPRequest`. The new core uses
`HTTPTypes.HTTPRequest` in its public seam and `HTTPRuntime` internally. Always qualify in new code;
an unqualified `HTTPRequest` in this target is a latent bug.

---

## Task 1: Move today's builders to `Legacy/`

A pure file move, no behavior change. Doing it first means every later task is additive and the
review diff for each one is small.

**Files:**
- Move: `Sources/PostgREST/Defaults.swift`, `PostgrestClient.swift`, `PostgrestFilterBuilder.swift`,
  `PostgrestFilterValue.swift`, `PostgrestQueryBuilder.swift`, `PostgrestRequestBuilder.swift`,
  `PostgrestTransformBuilder.swift`, `Types.swift` → `Sources/PostgREST/Legacy/`
- Keep in place: `Exports.swift`, `Query/`, `Relations/`

`PostgrestFilterValue.swift` is the one judgment call. It is shared — the typed filters in
`Query/PostgrestTypedQuery+Filters.swift` use `PostgrestFilterValue`, and so does the legacy
builder. It is **not** legacy. Move it to `Sources/PostgREST/Filters/PostgrestFilterValue.swift`
instead, matching §4.11.

- [ ] **Step 1: Move the files**

```bash
mkdir -p Sources/PostgREST/Legacy Sources/PostgREST/Filters
git mv Sources/PostgREST/PostgrestFilterValue.swift Sources/PostgREST/Filters/
for f in Defaults PostgrestClient PostgrestFilterBuilder PostgrestQueryBuilder \
         PostgrestRequestBuilder PostgrestTransformBuilder Types; do
  git mv "Sources/PostgREST/$f.swift" Sources/PostgREST/Legacy/
done
```

- [ ] **Step 2: Add the boundary note**

Create `Sources/PostgREST/Legacy/README.md` — excluded from the target in `Package.swift`, the same
way §4.11 excludes `CONTEXT.md`:

> These files are the API this package shipped before the value-typed core. They are deprecated in
> stage 4 and deleted in the next major. They are **behaviorally frozen**: do not fix bugs here, do
> not reimplement them over the new core. Spec §6 explains why — today's builders carry their own
> retry loop and inconsistent escaping, and silently changing that mid-deprecation is exactly what
> deprecating something is meant to avoid.

- [ ] **Step 3: Verify nothing broke**

```bash
swift build && swift test
```

Expected: no source change is needed. SwiftPM globs the target, so the move is invisible to the
build. If anything fails to compile, a file was moved that should not have been.

- [ ] **Step 4: Commit**

```
refactor(postgrest)!: move today's builders under Legacy/
```

Marked `!` because it changes no API but does change where every future reader looks, and
`V3_MIGRATION.md` should say the old API is now quarantined. No symbol moved, so no compliance
change.

---

## Task 2: The request model

**Files:**
- Create: `Sources/PostgREST/Request/PostgrestRequest.swift`
- Test: `Tests/PostgRESTTests/PostgrestRequestTests.swift`

**Interfaces:**
- Produces: `PostgrestRequest`, a `Sendable` value carrying method, path, query items, headers and
  body, plus the rendering that turns it into an `HTTPTypes.HTTPRequest`.

The whole point of this type is that building a request becomes a pure function. Spec §4.12: most of
today's 3,970 lines of snapshot tests become direct assertions once a request is inspectable without
executing.

- [ ] **Step 1: Write the failing test**

Assert the shape a query renders to, with no client and no network:

```swift
@Suite
struct PostgrestRequestTests {
  @Test
  func rendersQueryItemsInInsertionOrder() {
    var request = PostgrestRequest(method: .get, path: "/todos")
    request.appendQueryItem(name: "select", value: "*")
    request.appendQueryItem(name: "done", value: "eq.false")
    #expect(request.renderedQuery == "select=*&done=eq.false")
  }

  @Test
  func repeatedFilterKeysAreBothKept() {
    // PostgREST ANDs repeated keys. A dictionary would silently drop one.
    var request = PostgrestRequest(method: .get, path: "/todos")
    request.appendQueryItem(name: "id", value: "gt.1")
    request.appendQueryItem(name: "id", value: "lt.9")
    #expect(request.renderedQuery == "id=gt.1&id=lt.9")
  }
}
```

The second test is the one that matters. Query items must be an **ordered array**, not a dictionary:
`.gt(\.id, 1).lt(\.id, 9)` is a legitimate chain and both parameters have to survive.

- [ ] **Step 2: Implement**

Percent-encoding is the subtle part. Today's escaping is inconsistent — spec §2.1 lists it as a real
bug, and SDK-1510 fixes it for the legacy path. The new core escapes **once**, centrally, in
rendering. No call site does its own escaping.

- [ ] **Step 3: Port the legacy request-building snapshots**

`Tests/PostgRESTTests/__Snapshots__/BuildURLRequestTests/` has 31 recorded requests. They are the
best available specification of what the wire format must be. Re-assert each one against
`PostgrestRequest` rendering, as direct `#expect`s rather than snapshots. Any difference is either a
bug in the new core or a legacy bug being deliberately fixed — decide and record which, per case.

- [ ] **Step 4: Format, spell-check, commit**

---

## Task 3: The transport seam

**Files:**
- Create: `Sources/PostgREST/Transport/PostgrestTransport.swift`
- Create: `Sources/PostgREST/Transport/URLSessionPostgrestTransport.swift`
- Test: `Tests/PostgRESTTests/PostgrestTransportTests.swift`

**Interfaces:**
- Produces: `public protocol PostgrestTransport`, expressed over `HTTPTypes`, plus the shipped
  URLSession-backed implementation and the internal bridge to `HTTPRuntime`.

```swift
public protocol PostgrestTransport: Sendable {
  func send(_ request: HTTPTypes.HTTPRequest, body: Data?) async throws
    -> (Data, HTTPTypes.HTTPResponse)
}
```

Nothing `package`-scoped appears in that signature, which is the whole reason it can be public. See
the decision table above.

- [ ] **Step 1: Write the failing test**

A stub transport that records the request and returns a canned response, then assert a query reaches
it. This replaces `QueryCapture`/`RequestCapture` for the new core — those exist only because
`FetchHandler` was the only seam.

- [ ] **Step 2: Implement the protocol and the URLSession implementation**

- [ ] **Step 3: Delete the hand-rolled retry loop**

`Legacy/PostgrestRequestBuilder.swift` hand-rolls attempt counting and back-off, duplicating
`Sources/Helpers/HTTP/RetryRequestInterceptor.swift` (spec §2.1). The new core uses the
interceptor. **Do not touch the legacy copy** — Task 1's boundary note says why.

- [ ] **Step 4: Confirm the `db.retry` option still works**

`SupabaseClientOptions` gained a `db.retry` flag in #1244. Assert it disables retries on the new
core too, or the option silently stops working for anyone who moves to the typed API.

- [ ] **Step 5: Format, spell-check, commit + compliance**

---

## Task 4: Response and errors

**Files:**
- Create: `Sources/PostgREST/Response/PostgrestResponse.swift`
- Create: `Sources/PostgREST/Errors/PostgrestRequestError.swift`
- Test: `Tests/PostgRESTTests/PostgrestRequestErrorTests.swift`

**Interfaces:**
- Produces: a `Sendable` `PostgrestResponse`, and `PostgrestRequestError` with its extensible `Kind`.

Two facts to hold onto, both verified against the current source:

- Today's `PostgrestResponse<T>` (now `Legacy/Types.swift:37`) exposes `HTTPURLResponse` and is
  **not** `Sendable`. The new one is a struct over `HTTPTypes.HTTPResponse` and is.
- `PostgrestError` in `Sources/Helpers/SharedModels/` is a `Codable` **wire model**, not a failure
  taxonomy, and cannot become one because `underlyingError` is not `Codable`. It stays exactly as it
  is and becomes the `serverError` payload. Do not attempt to merge the two.

`Kind` is a `RawRepresentable` struct, not an enum — [ADR 0001](../adr/0001-public-error-types-are-structs.md),
and the repo convention in `AGENTS.md` under "Enum-like Values".

- [ ] **Step 1: Write the failing tests** — one per `Kind`, asserting that a server rejection, a
  transport failure, a decode failure, an encode failure and a cancellation each map to the right
  kind and carry the right payload. Cancellation folding into `.cancelled` is the one most likely to
  be missed.
- [ ] **Step 2: Implement**
- [ ] **Step 3: `execute()` returns the value; add `executeWithResponse()` and `count(_:)`**

Per §4.8, `FetchOptions` disappears. `count(.exact)` replaces
`execute(options: FetchOptions(head: true, count: .exact))`.

- [ ] **Step 4: Format, spell-check, commit + compliance**

---

## Task 5: The filter tree

**Files:**
- Create: `Sources/PostgREST/Filters/PostgrestFilter.swift`
- Create: `Sources/PostgREST/Filters/PostgrestFilter+Render.swift`
- Test: `Tests/PostgRESTTests/PostgrestFilterRenderTests.swift`

**Interfaces:**
- Produces: `PostgrestFilter<R>` with its `indirect enum Node`, built by `.and`/`.or`/`.not`, and
  rendered once at request-build time.

Rendering is a pure tree-to-string function with no client and no network (§4.12). Test it as one.

- [ ] **Step 1: Write the failing tests — the four wire forms from §4.3**

| Tree | Rendered |
|---|---|
| `and(eq(done,false), gt(priority,3))` | `done=eq.false&priority=gt.3` |
| `or(eq(done,false), gt(priority,3))` | `or=(done.eq.false,priority.gt.3)` |
| `or(and(eq(done,false), gt(priority,3)), eq(pinned,true))` | `or=(and(done.eq.false,priority.gt.3),pinned.eq.true)` |
| `not(and(eq(done,false), gt(priority,3)))` | `not.and=(done.eq.false,priority.gt.3)` |

Row 3 is the payoff and row 4 is the one that is easy to get wrong. Both grammars are **verified
against live PostgREST 14.15** — spec §9.1 has the matrix, including `not.and(…)` nested inside
`or(…)`. Do not re-litigate them against a server; assert them as fixed expectations.

- [ ] **Step 2: Implement the tree and flattening**

`and`/`or` flatten associatively, so `and(a, and(b, c))` renders as one parameter set rather than a
nested group. A top-level `and` is the *absence* of a wrapper — each conjunct becomes its own query
parameter — which is why repeated keys in Task 2 had to be an ordered array.

- [ ] **Step 3: `nil` must not reach `eq`**

Spec §9.3 is the evidence and it is worse than "eq.null never matches": on an `integer` column
`column=eq.null` is an HTTP 400, and on a `text` column it returns **HTTP 200 with the row whose
value is the literal string `'null'`** — a silently wrong row. `.eq(\.deletedAt, nil)` must not
compile; `.isNull(_:)` renders `is.null`. SDK-1509 already established the type-level machinery for
the legacy path (`PostgrestArrayElement` vs `PostgrestFilterValue`); reuse it, do not reinvent it.

- [ ] **Step 4: Format, spell-check, commit + compliance**

---

## Task 6: The standalone phase types

**Files:**
- Rewrite: `Sources/PostgREST/Query/PostgrestSource.swift` (was `PostgrestTypedSource.swift`)
- Rewrite: `Sources/PostgREST/Query/PostgrestQuery.swift` (was `PostgrestTypedQuery.swift`)
- Rewrite: `Sources/PostgREST/Query/PostgrestMutation.swift` (was `PostgrestTypedMutation.swift`)
- Create: `Sources/PostgREST/Query/PostgrestRawQuery.swift`
- Test: rename and extend the three existing typed suites

**Interfaces:**
- Produces the type chain in §4.1, over `PostgrestRequest` instead of `PostgrestRequestBuilder`.

This is the rename decided above, and it is the one `feat!:` commit in the stage.

- [ ] **Step 1: Rename, keeping the delegation, and confirm tests still pass**

Do the rename as its own step with no behavior change, so the reviewable diff separates "renamed"
from "reimplemented".

- [ ] **Step 2: Reimplement over `PostgrestRequest`**

`PostgrestKeyPathFilterable` survives — it is still what keeps the filter set declared once for both
`PostgrestQuery` and `PostgrestMutation` — but its requirement changes from `builder` to the new
request value.

> **This supersedes part of SDK-1519.** That issue decides to keep `builder` public as an escape
> hatch to the string API and to underscore `init(_builder:)`. Once the typed types no longer hold a
> `PostgrestRequestBuilder`, the escape hatch has nothing to hand back. Decide here whether to drop
> it (and say so in `V3_MIGRATION.md`) or to keep a `legacyBuilder` bridge for one release. Dropping
> it is cleaner and the alpha marker permits it; keeping it costs a conversion function that exists
> only to be deleted in stage 4.

- [ ] **Step 3: `PostgrestRawQuery` is a dead end**

`csv()`, `geojson()` and `explain(…)` return it, and it has no `stripNulls()` and no route back to
`PostgrestQuery`. That is what makes `pendingError` — the deferred-runtime-error string in
`Legacy/PostgrestRequestBuilder.swift` — unrepresentable rather than merely unused. Add a test
asserting the conflicting chain does not compile, as a comment plus a compile-time-only fixture;
Swift cannot assert non-compilation at runtime, so say so explicitly rather than implying coverage.

- [ ] **Step 4: `single()` and `maybeSingle()` change the output type**

`[T]` → `T` and `T?`. This is what removes the hidden `isMaybeSingle` flag read back inside
`execute`. `maybeSingle()` returning `T?` is the PGRST116 case encoded in the type.

- [ ] **Step 5: Format, spell-check, commit + compliance**

The compliance file needs every renamed symbol updated, not added — `PostgrestTypedQuery.*` becomes
`PostgrestQuery.*`. Run the validator; a rename that only adds is a silent drift.

---

## Task 7: Unfiltered writes do not compile

**Files:**
- Modify: `Sources/PostgREST/Query/PostgrestMutation.swift`
- Test: `Tests/PostgRESTTests/PostgrestMutationGuardTests.swift`

Per the decision table. `.delete().execute()` stops compiling; `.delete().all().execute()` is the
explicit form.

- [ ] **Step 1: Add an unscoped phase**

A mutation starts in a phase that has no `execute()`. Any filter, or `.all()`, moves it to the
executable phase. This is the same phantom-phase technique `PostgrestRequestBuilder<Phase>` already
uses, so there is prior art in this package to copy.

- [ ] **Step 2: Test that the scoped and `.all()` forms execute, and document the non-compiling case**
- [ ] **Step 3: `V3_MIGRATION.md` entry** — this is a `feat!:`-shaped constraint on a new API, so the
  entry is short, but the writing-migration-guides skill still applies.
- [ ] **Step 4: Format, spell-check, commit + compliance**

---

## Task 8: The untyped path

**Files:**
- Create: `Sources/PostgREST/Relations/AnyPostgrestRelation.swift`
- Modify: `Sources/PostgREST/Query/PostgrestSource.swift`

Per §4.9. `from("todos")` yields `PostgrestSource<AnyPostgrestRelation>`.

- [ ] **Step 1: Conform `AnyPostgrestRelation` to `PostgrestRelation` only**

**Not** `PostgrestWritableRelation`. Conforming it would force `Insert`/`Update` to a concrete type
such as `JSONValue`, which is a regression against today's `insert(_ values: some Encodable)`.

- [ ] **Step 2: Writes come from a dedicated `where R == AnyPostgrestRelation` extension**

taking `some Encodable`, so the escape hatch stays as capable as today's API.

- [ ] **Step 3: `PostgrestSource` stores the relation name as a value**

rather than reading it from `R.relationName`, which is what lets the typed and untyped paths share
one type.

- [ ] **Step 4: Format, spell-check, commit + compliance**

---

## Task 9: Auth via token provider

**Files:**
- Modify: the new client configuration
- Test: `Tests/PostgRESTTests/PostgrestClientAccessTokenTests.swift` (extend)

```swift
public var accessToken: (@Sendable () async throws -> String?)?
```

- [ ] **Step 1: Write a test for the race this closes** — a request in flight must not pick up a
  token change. That is the actual defect; asserting only that the header is set does not cover it.
- [ ] **Step 2: Implement, matching how `SupabaseClient` already sources tokens**
- [ ] **Step 3: Format, spell-check, commit + compliance**

---

## Task 10: Wire it up and verify the slice

**Files:**
- Create: `Sources/PostgREST/Client/PostgrestClient.swift` (the new client)
- Modify: `Sources/Supabase/SupabaseClient.swift`
- Modify: `sdk-compliance.yaml`

- [ ] **Step 1: The new client gets its own options type**

Not `DatabaseOptions`, which carries the `encoder`/`decoder` knobs the new API does not accept
([ADR 0002](../adr/0002-postgrest-exposes-no-public-json-coders.md)). The deprecated
`SupabaseClient.database` property is unaffected.

- [ ] **Step 2: Give `SupabaseClient` a typed entry point**

`SupabaseClient.rest` is **internal** and `SupabaseClient.from(_ table: String)` returns
`PostgrestQueryBuilder`, so the only public route to the typed API today is
`client.schema("public").from(Todo.self)`. If SDK-1519 has not already fixed this, fix it here — an
API nobody can reach is not shipped.

- [ ] **Step 3: Full verification**

```bash
swift build
swift test
./scripts/format.sh
./scripts/spell-check.sh
./scripts/test-docs.sh
PLATFORM=IOS ./scripts/xcodebuild.sh
```

`./scripts/build-for-library-evolution.sh` is **known to fail on `main`** inside swift-log
(SDK-1561), for reasons unrelated to this work. Check its status before treating a failure here as
yours.

- [ ] **Step 4: Confirm the legacy path is untouched**

```bash
git diff --stat origin/main -- Sources/PostgREST/Legacy/
```

Expected: only the renames from Task 1. Any other change means the boundary leaked.

---

## Out of scope for this plan

- `where(_:)` as a method, `embedded`/`requiring` scope, `@Function`, and the operator layer — all
  stage 3. This stage builds the filter *tree*; stage 3 puts the ergonomic surface on it.
- Deprecating the legacy builders — stage 4. This stage only quarantines them.
- `AsyncSequence` pagination (`.pages(of:)`) — §7, deferred until asked for.
- `@Table(readOnly:)` versus a `@View` alias — §7, cosmetic.

## Verification checklist for the whole slice

- [ ] `swift build` and `swift test` pass
- [ ] `./scripts/format.sh` and `./scripts/spell-check.sh` pass
- [ ] `./scripts/test-docs.sh` passes
- [ ] `PLATFORM=IOS ./scripts/xcodebuild.sh` passes
- [ ] The capability-matrix check passes, with every rename applied rather than added
- [ ] No public API references a `package` type from `HTTPRuntime` or `Helpers`
- [ ] `Sources/PostgREST/Legacy/` differs from `main` only by the Task 1 renames
- [ ] All 31 legacy request snapshots have an equivalent assertion against `PostgrestRequest`, and
      every deliberate difference is recorded
