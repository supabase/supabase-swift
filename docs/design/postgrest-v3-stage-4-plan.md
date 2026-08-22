# PostgREST v3 Stage 4 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mark the pre-v3 PostgREST API deprecated, leave it behaviorally frozen, and give every
deprecation a migration path a caller can follow without reading the spec.

**Architecture:** No code moves and no code is reimplemented. Stage 2 already quarantined the old
files under `Legacy/`; this stage attaches `@available(*, deprecated:)` to them, adds the
`SupabaseClient` overloads that make the new API reachable, and writes the migration guide entries.

**Tech Stack:** Swift 6.1, SwiftPM, Swift Testing.

**Spec:** [`postgrest-v3.md`](./postgrest-v3.md) — §4.10 (surface removed), §5 (staging), §6
(migration). **Read §6 first.** It contains the one decision that shapes this whole stage, and its
reasoning was revised once already.

**Depends on:** stages 2 and 3. Deprecating an API before its replacement is complete tells callers
to migrate to something that cannot do the job yet.

---

## The one decision this stage rests on

Spec §6: today's implementation stays **in place and untouched**, marked deprecated, rather than
reimplemented over the new core.

The original justification for that was aliasing — "value types cannot reproduce the old behavior
where two chains branched off one builder mutate the same object". **That reason is gone.**
[#1240](https://github.com/supabase/supabase-swift/pull/1240) already made today's builders value
types, so there is no aliasing behavior left for a reimplementation to lose.

The reason that still holds is narrower, and it is the one to cite in review: today's builders carry
their own hand-rolled retry loop and inconsistent filter escaping (§2.1), and stages 2–3 fix both in
the new core. Reimplementing the deprecated builders over that core would **silently change their
behavior during the deprecation window** — precisely what deprecating something is supposed to avoid.
Leaving the old code alone keeps it frozen until it deletes cleanly in the next major.

The cost is duplicated request-building logic for one release cycle. That is accepted.

Do not let a reviewer talk this into a reimplementation on the grounds that the aliasing argument no
longer applies. The conclusion survives; only its first justification died.

## Global Constraints

- Swift 6.1 floor. **Swift Testing only.** Explicit `@Suite`. Test functions drop the `test` prefix.
- 2-space indentation. `./scripts/format.sh` and `./scripts/spell-check.sh` before every commit.
- Conventional commits. This stage is `feat!:`/`refactor!:` throughout — every deprecation is a
  breaking-change marker that release-please and the API stability check key off.
- **Every `!` commit requires a `V3_MIGRATION.md` entry.** Use the writing-migration-guides skill for
  the format; `V3_MIGRATION.md` is already ~1,700 lines and has an established shape to match.
- Deprecation attributes carry a `message:` naming the replacement. A bare `@available(*, deprecated)`
  is not acceptable — it tells the caller they are wrong without telling them what to do.
- **No file under `Legacy/` changes behavior.** Attributes and doc comments only.

---

## Task 1: Inventory the surface to deprecate

Nothing to implement. Doing this first turns "deprecate the old API" into a checklist, and the count
is the review's completeness check.

**Files:**
- Create: `docs/design/postgrest-v3-stage-4-inventory.md` (working document, deleted before merge or
  kept as an appendix — decide when writing it)

- [ ] **Step 1: Enumerate**

```bash
grep -rhoE "^\s*public (func|var|let|struct|enum|typealias|protocol|final class|class) [A-Za-z_]+" \
  Sources/PostgREST/Legacy/ | sort | uniq -c | sort -rn
```

Measured on the pre-stage-2 layout, the six legacy files carry **113** public declarations. Expect
that order of magnitude. If the number comes back much smaller, `Legacy/` is missing files that stage
2 should have moved.

- [ ] **Step 2: Classify each one**

| Class | Action |
|---|---|
| Has a direct new-API equivalent | Deprecate with `message:` naming it |
| Removed with no equivalent (§4.10) | Deprecate with `message:` explaining what to do instead |
| Shared with the new API | **Do not deprecate.** `PostgrestFilterValue` is the obvious case — stage 2 moved it to `Filters/` for this reason |
| Already gone from `main` | Nothing to do; `Deprecated.swift` was deleted while the spec was being written |

The third row is where mistakes happen. A symbol used by both APIs that gets deprecated emits
warnings inside our own new code.

- [ ] **Step 3: Cross-check against §4.10**

§4.10 lists 16 forwarding methods on `PostgrestFilterBuilder` (`equals`, `notEquals`, `greaterThan`,
`greaterThanOrEquals`, `lowerThan`, `lowerThanOrEquals`, `rangeLowerThan`, `rangeGreaterThan`,
`rangeGreaterThanOrEquals`, `rangeLowerThanOrEquals`, `fullTextSearch`, `plainToFullTextSearch`,
`phraseToFullTextSearch`, `webFullTextSearch`, `match(_:)`, `fts`), plus `FetchOptions`,
`FetchHandler`, `PostgrestReturningOptions` as a free-standing enum, and the `queryValue`
deprecation shim. Confirm each is present in the inventory; anything in §4.10 that is missing means
the spec and the code have drifted.

---

## Task 2: Make the new API reachable from `SupabaseClient`

**This task comes before any deprecation.** Deprecating `SupabaseClient.from(_:)` while the typed API
is only reachable through a workaround would be actively hostile.

**Files:**
- Modify: `Sources/Supabase/SupabaseClient.swift`
- Test: `Tests/SupabaseTests/SupabaseClientTypedAccessTests.swift`

**Verified state of the code today:** `SupabaseClient.rest` is **internal**, and
`SupabaseClient.from(_ table: String)` returns `PostgrestQueryBuilder`. The only public route to the
typed API is `client.schema("public").from(Todo.self)`, because `schema(_:)` returns a
`PostgrestClient`.

- [ ] **Step 1: Add the overloads §6 calls for**

`from(_:)`, `rpc(_:params:count:)` and `schema(_:)` need new overloads returning the new types.
`from(_ type:)` is the one that matters most — it is the entry point in essentially every app.

- [ ] **Step 2: The new client gets its own options type**

Not `DatabaseOptions`, which carries the `encoder`/`decoder` knobs the new API does not accept
([ADR 0002](../adr/0002-postgrest-exposes-no-public-json-coders.md)). The deprecated
`SupabaseClient.database` property is unaffected.

- [ ] **Step 3: Test that a `SupabaseClient` user can reach the typed API in one call**

```swift
#expect(client.from(Todo.self) is PostgrestSource<Todo>)
```

If stage 2's Task 10 already did this, verify and move on rather than redoing it.

- [ ] **Step 4: Format, spell-check, commit + compliance**

---

## Task 3: Deprecate the builders

**Files:**
- Modify: every file under `Sources/PostgREST/Legacy/`
- Modify: `Sources/Supabase/SupabaseClient.swift`
- Modify: `V3_MIGRATION.md`

- [ ] **Step 1: Attach the attributes, one file per commit**

Six files, six commits. A single 113-symbol commit is unreviewable, and per-file commits let a
reviewer check the `message:` strings against the inventory's classification.

```swift
@available(
  *, deprecated,
  message: "Use client.from(Todo.self) with a @Table type. See V3_MIGRATION.md."
)
```

- [ ] **Step 2: Expect a wall of warnings in our own code, and fix it properly**

`Tests/PostgRESTTests/` has ~15 suites against the legacy API, and `Examples/` uses it throughout.
Two ways to silence them, and the choice matters:

- Keep the legacy tests, wrapped so the deprecation warning is suppressed at the call site. The
  deprecated API must stay tested — it ships for a whole release cycle.
- Migrate `Examples/` to the new API. **`Examples/` is not covered by `swift test`** — it builds only
  in the Xcode CI jobs, so a migration mistake there surfaces late. Build each scheme locally before
  pushing: `DERIVED_DATA_PATH=~/.derivedData SCHEME=SlackClone XCODEBUILD_ARGUMENT=build ./scripts/xcodebuild.sh`

Do **not** silence warnings by deleting legacy test coverage.

- [ ] **Step 3: One `V3_MIGRATION.md` entry per class, not per symbol**

113 entries would be unreadable. Group by the inventory's classification: one entry for "the filter
forwarding methods", one for "`FetchOptions` and `count`", one for "`FetchHandler` and transport",
one for "the builder chain becomes `from(_ type:)`". Each with a before/after snippet.

- [ ] **Step 4: Call out the coder migration cost explicitly**

§6 names it and it deserves its own entry: an app that configured one global snake-case coder — as
`Examples/SlackClone/Supabase.swift` does today — must declare the naming convention per relation
instead. That is more typing, and it is the price of column names being correct by construction.

- [ ] **Step 5: Reconcile with #1248**

[#1248](https://github.com/supabase/supabase-swift/pull/1248) gave the *current* API per-call
`encoder`/`decoder` overrides on `insert`/`update`/`upsert`/`execute`, in the same release cycle this
redesign was drafted. ADR 0002's "not configurable" decision was always scoped to the new API, so
they are not in technical tension — but an app that just adopted a per-call coder override gets **no
equivalent** on the new API, and hits the §6 migration cost sooner than one that did not. Say so in
the guide rather than letting them discover it.

---

## Task 4: Prove the frozen API is actually frozen

**Files:**
- Create: `Tests/PostgRESTTests/LegacyBehaviorFreezeTests.swift`

The claim in §6 is that the deprecated API is behaviorally unchanged. That claim needs a test, or it
is just an intention — the same reasoning SDK-1519 applied to the macro dependency boundary.

- [ ] **Step 1: Assert the two known legacy defects still behave as they did**

This reads backwards and it is deliberate. The legacy path keeps its hand-rolled retry loop and its
inconsistent escaping; freezing means those do **not** silently acquire the new core's fixes. Write
the assertions with a comment saying so, or a future reader will "fix" them.

Note the interaction with SDK-1509 and SDK-1510: those two *did* fix filter correctness on the
legacy path, deliberately, because they are silent-wrong-rows bugs. So the freeze baseline is
"legacy as of stage 4", not "legacy as of the spec being written". State the baseline commit.

- [ ] **Step 2: Assert the new core is not wired into the legacy path**

```bash
git diff --stat <stage-2-merge-base> -- Sources/PostgREST/Legacy/
```

Expected: attribute and doc-comment changes only.

- [ ] **Step 3: Format, spell-check, commit**

---

## Task 5: Verify and record the deletion plan

- [ ] **Step 1: Full verification**

```bash
swift build
swift test
./scripts/format.sh
./scripts/spell-check.sh
./scripts/test-docs.sh
PLATFORM=IOS ./scripts/xcodebuild.sh
DERIVED_DATA_PATH=~/.derivedData SCHEME=SlackClone XCODEBUILD_ARGUMENT=build ./scripts/xcodebuild.sh
```

`./scripts/build-for-library-evolution.sh` is **known to fail on `main`** inside swift-log
(SDK-1561). Check its status before treating a failure as yours.

- [ ] **Step 2: The API stability check will flag this loudly, and should**

`.github/workflows` runs `scripts/check-for-breaking-api-changes.sh`. Every deprecation is a flagged
change. Confirm the flags match the inventory exactly — an unflagged deprecation, or a flag with no
inventory entry, means something was missed.

- [ ] **Step 3: Write down when the deprecated API deletes**

"Next major" is in the spec; the deletion needs an issue so it does not become permanent. File it
against the v4 milestone with the inventory attached, and reference it from the `V3_MIGRATION.md`
entries so callers know the window.

---

## Out of scope for this plan

- Deleting the deprecated API — next major, tracked by Task 5 step 3.
- Any behavior change to `Legacy/` — the whole point of the stage is that there is none.
- The postgres-meta template — stage 5.
- `SupabaseClient.database` — unaffected, per §6.

## Verification checklist for the whole slice

- [ ] `swift build` and `swift test` pass
- [ ] `./scripts/format.sh` and `./scripts/spell-check.sh` pass
- [ ] `./scripts/test-docs.sh` passes
- [ ] `PLATFORM=IOS ./scripts/xcodebuild.sh` passes
- [ ] All three `Examples/` Xcode schemes build
- [ ] The capability-matrix check passes
- [ ] Every deprecation has a `message:` naming a replacement or an alternative
- [ ] Every `!` commit has a `V3_MIGRATION.md` entry
- [ ] The API stability check's flagged list matches the Task 1 inventory, both directions
- [ ] `Sources/PostgREST/Legacy/` differs only by attributes and doc comments
- [ ] A `SupabaseClient` user can reach the typed API in one call
