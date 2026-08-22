# PostgREST v3 Stage 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put the ergonomic surface on the filter tree stage 2 built — `where`, the
`embedded`/`requiring` scope, `@Relationship`, `@Function` — and decide the operator layer on
measured evidence rather than taste.

**Architecture:** Purely additive over stage 2. `where(_:)` takes a `PostgrestFilter<R>` value.
Scope is a construct on the query, not a node in the filter tree, which is what keeps an
impossible query unrepresentable. `@Relationship` extends the existing `@SelectionOf` expansion.

**Tech Stack:** Swift 6.1, SwiftPM, swift-syntax, swift-macro-testing, Swift Testing.

**Spec:** [`postgrest-v3.md`](./postgrest-v3.md) — §4.3 (filters as values), §4.4 (embedded scope),
§4.5 (select tiers and `@Relationship`), §4.6 (database functions), §9 (server verification).
**Read §4.4 and §9.2 before starting.** The two-spelling scope design is the single most important
decision in this stage and it rests on verified server behavior.

**Depends on:** stage 2. The filter tree, `PostgrestQuery` and `PostgrestRequest` all come from
there. Nothing in this plan can start before it lands.

---

## Why this stage carries the highest-severity item in the project

Spec §10.3 ranks `embedded`/`requiring` as **highest impact** of anything in the redesign, and the
reason is not ergonomics. PostgREST's documented default is that an embedded filter *does not change
the parent rows at all*:

> "By default, Embedded Filters don't change the top-level resource (`films`) rows at all… In order
> to filter the top level rows you need to add `!inner` to the embedded resource."

So the query everybody writes first —

```swift
.embedded(\.comments) { $0.where(.eq(\.approved, true)) }
```

— returns **every** todo, some with an empty `comments` array. Not an error. Not empty. Silently the
wrong row set. Verified live: §9.2 row 1 confirms all parents come back with only the nested rows
filtered.

A `join:` parameter with a default cannot fix this, because whichever default is chosen is silently
wrong half the time. Two differently-named methods make the choice unavoidable at the call site.
That naming *is* the feature.

## Global Constraints

- Swift 6.1 floor. **Swift Testing only.** Explicit `@Suite`. Test functions drop the `test` prefix.
- Public types in `PostgREST` are prefixed `Postgrest`; macro attributes in `PostgrestMacros` stay bare.
- 2-space indentation. `./scripts/format.sh` and `./scripts/spell-check.sh` before every commit.
- Every new public API needs a DocC comment and the alpha warning from SDK-1519.
- Conventional commits, `feat:` throughout — this stage is additive, so no `!` and no
  `V3_MIGRATION.md` entry unless Task 6 concludes otherwise.
- Every commit adding a public symbol gets a matching `chore(compliance):` commit.
- **Grammars in §9 are settled.** They were verified against live PostgREST 14.15. Assert them as
  fixed expectations; do not spend time re-testing them against a server.

---

## Task 1: `where(_:)` on query and mutation

**Files:**
- Modify: `Sources/PostgREST/Query/PostgrestQuery.swift`, `PostgrestMutation.swift`
- Modify: `Sources/PostgREST/Query/PostgrestKeyPathFilterable.swift`
- Test: `Tests/PostgRESTTests/PostgrestWhereTests.swift`

**Interfaces:**
- Consumes: `PostgrestFilter<R>` from stage 2.
- Produces: `where(_ filter: PostgrestFilter<R>) -> Self` on both, and repeated calls that AND.

- [ ] **Step 1: Write the failing tests**

```swift
@Test
func repeatedWhereCallsAnd() {
  // Two calls must not produce or=(…) and must not drop either filter.
  let request = source.select().where(.eq(\.done, false)).where(.gt(\.priority, 3)).renderedRequest
  #expect(request.renderedQuery.contains("done=eq.false"))
  #expect(request.renderedQuery.contains("priority=gt.3"))
}

@Test
func aFilterIsAValueThatNeedsNoClient() {
  // The point of filters-as-values: nameable, storable, unit-testable.
  let overdue = PostgrestFilter<Todo>.and(.lt(\.dueDate, now), .eq(\.done, false))
  #expect(overdue.rendered() == "due_date=lt.\(now)&done=eq.false")
}
```

The second test is the design claim from §4.3 stated as an assertion. If a filter cannot be built and
rendered without a client, the stage 2 tree is wrong and this stage is building on sand.

- [ ] **Step 2: Implement**

Repeated `where` ANDs, which for a top-level conjunction means appending more query parameters — not
wrapping in `and=(…)`. Stage 2's ordered query items are what make this work.

- [ ] **Step 3: Keep stage 1's filter methods working**

`.eq(\.done, false)` must keep compiling and keep meaning the same thing. Spec §5: stage 1's typed
filter methods "must be designed to survive into the final API as sugar, so early adopters are not
migrated twice." Assert both spellings render identically:

```swift
#expect(query.eq(\.done, false).rendered == query.where(.eq(\.done, false)).rendered)
```

- [ ] **Step 4: Format, spell-check, commit + compliance**

---

## Task 2: `@Relationship` and embeds in selections

**Files:**
- Create: `Sources/PostgrestMacrosPlugin/RelationshipMacro.swift`
- Modify: `Sources/PostgrestMacrosPlugin/SelectionOfMacro.swift`
- Modify: `Sources/PostgrestMacros/Macros.swift`
- Test: `Tests/PostgrestMacrosTests/RelationshipMacroTests.swift`

**Interfaces:**
- Produces: `@Relationship(_ foreignKey: KeyPath)`, and `selectString` that includes embeds.

```swift
@SelectionOf(Todo.self)
struct TodoWithComments {
  var id: UUID
  var task: String
  @Relationship(\Comment.todoID) var comments: [CommentBody]
}

// TodoWithComments.selectString == "id,task,comments:comments!todo_id(id,body)"
```

The foreign key is the insight, taken from PR #1036: **the foreign key is itself a column**, so the
KeyPath already exists in both directions, it is compiler-checked, and it disambiguates when two
foreign keys join the same pair of relations. No new generator metadata.

- [ ] **Step 1: Write the failing expansion test**

Use `MacroTesting` with `record: .missing` and paste the actual, as the stage 1 macro tasks did.

- [ ] **Step 2: Two macro rules carried over from stage 1 — do not rediscover them**

Both cost real time in SDK-1516 and are recorded in `TableMacro.swift`:

- A macro-generated extension **cannot** witness a requirement with a member added by a *member* role
  of the same attribute. Emit everything from the extension role.
- The emitted inheritance clause must name **every** protocol in the refinement chain.
  `extension X: PostgrestWritableRelation` alone reports a missing `PostgrestRelation` with no note
  saying which requirement is unmet.

Reuse `inheritanceClause(wanted:missing:)` and `codingKeys(for:indent:)` from
`Support/Generation.swift`.

- [ ] **Step 3: `@Relationship` on a `@Table` property stays an error**

SDK-1518 already emits `@Relationship belongs on a @SelectionOf type, not on @Table`, written as a
forward-looking guard because the attribute did not exist yet. **It exists now** — update the comment
in `TableMacro.swift` that says the diagnostic is not yet reachable, and promote its test from a
`MacroTesting`-only case to one that also fails to compile for real.

- [ ] **Step 4: Extend `_columnCheck` to embeds**

The cross-type check must cover the foreign key too: emit a reference to
`Comment.columnName(for: \Comment.todoID)` so a wrong foreign key fails on the emitted line.

- [ ] **Step 5: Format, spell-check, commit + compliance**

---

## Task 3: The embedded scope construct

**Files:**
- Create: `Sources/PostgREST/Query/PostgrestEmbeddedScope.swift`
- Modify: `Sources/PostgREST/Query/PostgrestQuery.swift`
- Test: `Tests/PostgRESTTests/PostgrestEmbeddedScopeTests.swift`

**Interfaces:**
- Produces: `embedded(_:_:)` and `requiring(_:_:)` on `PostgrestQuery`, plus the scope type that
  filters, orders and limits within one embed.

- [ ] **Step 1: Write the failing test — the exact query from §4.4**

```swift
try await client.from(Todo.self)
  .select(TodoWithComments.self)
  .where(.eq(\.done, false))
  .requiring(\.comments) {
    $0.where(.or(.eq(\.approved, true), .eq(\.authorID, me)))
      .order(by: \.createdAt, .descending)
      .limit(5)
  }
```

must render:

```
select=…,comments!inner(…)&done=eq.false
  &comments.or=(approved.eq.true,author_id.eq.<me>)
  &comments.order=created_at.desc.nullslast
  &comments.limit=5
```

§9.4 confirms `messages.or=(…)`, `messages.order=…` and `messages.limit=…` all apply correctly
within a scope, including combined with `!inner`.

- [ ] **Step 2: `embedded` narrows nested rows; `requiring` emits `!inner` and drops unmatched parents**

Two methods, no `join:` flag. See the section at the top of this plan for why.

- [ ] **Step 3: The scope's KeyPath roots on the *selection*, not the relation**

`.embedded(\.comments)` roots on `TodoWithComments`, because a generated relation type has columns
only — `Todo.comments` does not exist. Useful consequence: `embedded` and `requiring` are available
only once a selection declaring embeds is chosen, so a whole-row `select()` does not offer them at
all. That is correct, since it selects no embeds. Encode it in the types rather than documenting it.

- [ ] **Step 4: Filters inside the scope target the embedded relation's columns**

Not the nested selection's — so a caller can filter on a column they did not select. The scope's type
parameter comes from the `@Relationship` declaration.

- [ ] **Step 5: Nesting composes**

PostgREST accepts dotted paths, so a nested scope renders `comments.replies.limit=3`.

- [ ] **Step 6: Combine the two embed hints, in either order**

§9.2 verified that `!<fk>` and `!inner` combine and that **hint order does not matter**:
`flights!origin_id!inner(id)` and `flights!inner!origin_id(id)` return the same rows. Pick one
emission order and assert it; do not make it configurable.

- [ ] **Step 7: Omitting a needed foreign key hint is HTTP 300**

§9.2: on an ambiguous relationship PostgREST returns **HTTP 300 `PGRST201`** listing the candidates.
`@Relationship` takes the foreign key precisely so this cannot happen, but the untyped
`.embedded("comments")` form can still hit it. Make sure that surfaces as a
`PostgrestRequestError` with the server payload intact rather than a decode failure.

- [ ] **Step 8: Format, spell-check, commit + compliance**

---

## Task 4: An impossible query stays unrepresentable

**Files:**
- Test: `Tests/PostgRESTTests/PostgrestScopeBoundaryTests.swift`

No new API. This task exists to lock in a property that is easy to lose in a later refactor.

PostgREST cannot OR a parent filter against an embedded one — they are separate query parameters and
therefore always ANDed. Keeping scope on the *query* rather than inside the filter tree means that
combination cannot be written at all. The current string-based `or` offers no such protection.

- [ ] **Step 1: Document the property with a compile-time fixture and a comment**

Swift cannot assert non-compilation at runtime. Write the fixture, comment why it must not compile,
and say plainly in the test file that this is documentation rather than enforcement — do not let a
reader think the suite would catch a regression here.

- [ ] **Step 2: Consider whether the dependency check pattern applies**

SDK-1519 builds `scripts/check-postgrest-dependencies.sh` to turn an intention into a CI guarantee.
If a similar "this must not compile" check is cheap — a fixture file compiled with an expected
failure — add it. If not, record the gap rather than leaving it implied.

---

## Task 5: `@Function` and typed RPC

**Files:**
- Create: `Sources/PostgrestMacrosPlugin/FunctionMacro.swift`
- Create: `Sources/PostgREST/Functions/PostgrestFunction.swift`
- Modify: `Sources/PostgREST/Client/PostgrestClient.swift`
- Test: `Tests/PostgrestMacrosTests/FunctionMacroTests.swift`,
  `Tests/PostgRESTTests/PostgrestRpcTests.swift`

**Interfaces:**

```swift
@Function("search_todos")
struct SearchTodos: Codable, Sendable {
  typealias Result = [Todo]
  var keyword: String
}

let hits = try await client.rpc(SearchTodos(keyword: "groceries")).execute()
```

- [ ] **Step 1: A function is not a relation**

It takes arguments, so a function without them is not a source and `from(_:)` must reject it. What it
shares with a relation is everything downstream — filters, ordering, projections, `execute()` — so
both funnel into the same `PostgrestQuery`. Make `from(SearchTodos.self)` fail to compile.

- [ ] **Step 2: `.readOnly()` replaces the `get:`/`head:` flags**

Today's path encodes params to `Data`, decodes them back into `JSONValue`, checks for `.object`, and
throws a server-error value at build time when the params are not key-value. With a descriptor the
parameters are known to be an object, so read-only is a modifier, not a flag that can fail.

- [ ] **Step 3: Keep the untyped fallback**

```swift
try await client.rpc("search_todos", params: ["keyword": "groceries"])
  .select(as: [Todo].self).execute()
```

- [ ] **Step 4: Format, spell-check, commit + compliance**

---

## Task 6: The operator layer — measure first, then decide

**Files:**
- Create: `Sources/PostgREST/Filters/PostgrestFilter+Operators.swift` *(only if the measurement
  supports it)*
- Create: `Tests/PostgRESTTests/PostgrestOperatorTests.swift`

This task is **conditional**, and that is the point. Spec §3 decision 5:

> Operator overloads on `==`, `&&`, `||` are global — `PostgREST` is `@_exported` from `Supabase`,
> and Swift cannot scope operator visibility per import, so every expression in every consuming file
> gains them to resolve against. Prior art exists, but the type-check cost is real and **unmeasured**.
> Methods carry none of it.

- [ ] **Step 1: Measure before writing the feature**

Build `Examples/SlackClone` and the test suite with `-Xfrontend -warn-long-expression-type-checking=100`
and record the count of flagged expressions. That is the baseline.

- [ ] **Step 2: Add the operators behind a branch, measure again**

Same command, same targets. Record the delta in the commit message. Also record wall-clock
`swift build` time for a clean build, three runs, median.

- [ ] **Step 3: Decide on the evidence, and write the decision down either way**

If the cost is material, **do not ship the operators** and record the measurement in the spec's §7 so
the question is closed rather than re-asked. If it is not, ship them as a purely additive layer over
the same tree — §4.3's table shows the wire output is identical either way.

- [ ] **Step 4: If shipping, assert operator and method spellings render identically**

Every row of §4.3's table, both spellings, same output. Otherwise the sugar is a second
implementation.

---

## Out of scope for this plan

- The value-typed core — stage 2, and a hard dependency of this stage.
- Deprecating today's builders — stage 4.
- The postgres-meta template — stage 5. Note that Task 2's `@Relationship` is the thing stage 5's
  generated embeds must agree with, so the two need reconciling when stage 5 is planned.
- `AsyncSequence` pagination (`.pages(of:)`) — §7, deferred.
- Generated selection types — §7, undecided and not needed before stage 5.

## Verification checklist for the whole slice

- [ ] `swift build` and `swift test` pass
- [ ] `./scripts/format.sh` and `./scripts/spell-check.sh` pass
- [ ] `./scripts/test-docs.sh` passes
- [ ] `PLATFORM=IOS ./scripts/xcodebuild.sh` passes
- [ ] The capability-matrix check passes
- [ ] Stage 1's filter methods still compile and render identically to their `where` equivalents
- [ ] Every grammar in §4.3's table and §9's matrices has an assertion
- [ ] The operator decision is recorded with its measurement, whichever way it went
