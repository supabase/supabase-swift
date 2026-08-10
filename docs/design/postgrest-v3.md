# PostgREST rewrite — design

Date: 2026-08-10
Status: design only. No implementation plan and no code yet.

## 1. Goal

Replace the `PostgREST` target with a value-typed, fully type-safe query API that keeps a
string-based escape hatch at every level. The new API ships beside the current one. The current
classes stay in place, marked deprecated, and are removed in the next major version.

## 2. What exists today

`Sources/PostgREST` is 3,181 lines across 10 files. `Tests/PostgRESTTests` is 3,384 lines across 10
files, mostly URL-building snapshots.

```
PostgrestBuilder            (class, @unchecked Sendable, LockIsolated<MutableState>)
├── PostgrestQueryBuilder   from(): select / insert / update / upsert / delete
└── PostgrestTransformBuilder  order / limit / range / single / csv / explain / …
    └── PostgrestFilterBuilder eq / neq / gt / like / in / contains / …  (1,166 lines)
```

State is one `Helpers.HTTPRequest` mutated in place. Every method writes a query item or a header,
then returns `self`.

### 2.1 Problems the rewrite fixes

**Reference semantics break the builder illusion.** Builders look like values but are classes. Two
chains branched off one builder mutate the same object. The lock exists to satisfy `Sendable`, not
to make concurrency safe. The doc comments admit this: "Do not modify the same builder instance
from multiple concurrent tasks."

**Inheritance encodes phase order, and it leaks.** `PostgrestFilterBuilder` subclasses
`PostgrestTransformBuilder`, so `select()` returns `Transform` and drops every filter method. You
must write `.update(x).eq("id", value: 1).select()` and never `.select().eq(…)`. Separately,
`PostgrestQueryBuilder` inherits `execute()`, so `client.from("t").execute()` compiles and sends a
bare GET with no operation chosen.

**Illegal states are runtime strings.** `MutableState.pendingError: String?` holds
"`.csv()` cannot be combined with `.stripNulls()`" until `execute()` throws it.

**Stringly-typed surface.** `select("id, task, done")` is parsed by a hand-rolled quote-aware
whitespace stripper, duplicated in `PostgrestQueryBuilder.select` and
`PostgrestTransformBuilder.select`. `or("done.eq.true,priority.gt.3")` makes callers write raw
PostgREST syntax, and it cannot express a nested `and(…)` without hand-writing it into the string.
`rangeGt(_:range:)` takes a `String`.

**Double `try`.** `insert` / `update` / `upsert` / `rpc` are `throws` because they encode the body
eagerly. Callers write `try client.from(…).insert(…)` then `try await …execute()`. The body is
encoded even when the chain is discarded.

**Inconsistent escaping.** `escapePostgRESTFilterValue` in `Sources/Helpers/PostgRESTFilterValue.swift`
is called only by `in` and `notIn`. `eq`, `neq`, `gt` and the rest never call it.

**Wasted work per chain step.** `PostgrestBuilder.init` builds a fresh `HTTPClient` and interceptor
array. `convenience init(_ other:)` runs it again on every phase transition.

**Duplicated retry.** `execute` hand-rolls attempt counting, back-off and retryable-status checks,
duplicating `Sources/Helpers/HTTP/RetryRequestInterceptor.swift`.

**Foundation-bound public surface.** `FetchHandler` is
`@Sendable (URLRequest) async throws -> (Data, URLResponse)`. `PostgrestResponse` stores
`HTTPURLResponse` and is not `Sendable`. Five files carry
`#if canImport(FoundationNetworking)`.

**Auth races.** `setAuth(_:)` mutates client-wide headers under a lock. `from(_:)` snapshots headers
at call time, so a token change during an in-flight chain is picked up unpredictably.

**Alias sprawl.** `PostgrestFilterBuilder` carries 16 methods that only forward to another method,
plus a separate 167-line `Deprecated.swift`.

## 3. Decisions taken

| Decision | Choice |
|---|---|
| Compatibility | New API beside the old one. Old classes deprecated, removed next major. |
| Type safety | Fully typed by default, string fallback available at every level. |
| Schema source | Both: a macro for hand-written types, and a rewritten postgres-meta generator. |
| Partial select | Declared projection types, plus ad-hoc KeyPath and raw-string tiers. |
| This document | Design only. Implementation is staged and planned separately. |

The existing postgres-meta Swift template
(`src/server/templates/swift.ts`) is not actively used and may be rewritten freely. Today it emits a
`PublicSchema` namespace enum containing `TodosSelect` / `TodosInsert` / `TodosUpdate` structs with
`CodingKeys`, conforming to `Codable, Hashable, Sendable` and `Identifiable` where an identity
column exists. It emits no table-name constants.

## 4. Target API

### 4.1 Phase modelling

Every type is a `Sendable` struct holding an immutable request value. No inheritance. Each phase is
a distinct type, so illegal chains fail to compile.

```
Postgrest.Client
  .from(Todo.self)  -> PostgrestTable<Todo>
  .from("todos")    -> PostgrestTable<AnyPostgrestRow>        // untyped fallback

PostgrestTable<Row>
  .select(…)                    -> PostgrestQuery<Row, [Output]>
  .insert(_:) / .upsert(_:)     -> PostgrestMutation<Row, Void>
  .update(_:) / .delete()       -> PostgrestMutation<Row, Void>     // filterable

PostgrestQuery<Row, Output>
  .where(_:) .order(_:) .limit(_:) .range(_:)  -> Self              // order-free
  .embedded(_:_:)                              -> Self
  .single()                                    -> PostgrestQuery<Row, Element>
  .maybeSingle()                               -> PostgrestQuery<Row, Element?>
  .csv() .geojson() .explain(…)                -> PostgrestRawQuery // dead end
  .execute()                                   -> Output

PostgrestMutation<Row, Output>
  .where(_:) …                  -> Self
  .returning(…)                 -> PostgrestQuery<Row, [Output]>
  .maxAffected(_:) .dryRun()    -> Self
  .execute()                    -> Output
```

`PostgrestTable` stores the table name as a value rather than reading it from `Row`, so the untyped
path works with the same type.

Three problems disappear structurally:

- **No `pendingError`.** `csv()` returns `PostgrestRawQuery`, which has no `stripNulls()`. The
  conflict is unrepresentable, so nothing needs to be deferred to `execute()`.
- **No accidental bare GET.** `PostgrestTable` has no `execute()`. An operation must be chosen.
- **No phase-order trap.** `where` and `order` both live on `PostgrestQuery`, so `.select().where(…)`
  and `.update(…).where(…).returning()` both read naturally.

`maybeSingle()` encodes the PGRST116 case in the output type (`Element?`) rather than in a hidden
`isMaybeSingle` flag read back inside `execute`.

### 4.2 The row contract

```swift
public protocol PostgrestRow: Decodable, Sendable {
  static var tableName: String { get }
  static var columnNames: [PartialKeyPath<Self>: String] { get }

  associatedtype Insert: Encodable & Sendable = Self
  associatedtype Update: Encodable & Sendable = Self
}
```

`KeyPath` is `Hashable`, so the KeyPath-to-column mapping is a plain dictionary. The query layer
needs no macro and no reflection.

`Insert` and `Update` default to `Self`, so hand-written types need nothing extra. The generator
supplies real variants, which is what makes nullable-with-default columns correct on insert and
all-optional columns correct on update.

Two ways to satisfy the protocol. The query API cannot tell them apart.

```swift
// Macro path — hand-written
@PostgrestTable("todos")
struct Todo: Codable, Sendable {
  let id: Int
  var task: String
  @PostgrestColumn("is_done") var done: Bool
}

// Generator path — macro-free, emitted by postgres-meta
struct Todo: PostgrestRow, Codable, Hashable, Sendable, Identifiable { /* explicit */ }
```

### 4.3 Filters as values

`PostgrestFilter<Row>` is an expression tree, not an appended query item.

```swift
public struct PostgrestFilter<Row>: Sendable {
  indirect enum Node: Sendable {
    case comparison(column: String, op: String, value: String)
    case and([Node])
    case or([Node])
    case not(Node)
    case raw(String)
  }
  var node: Node
}
```

`&&`, `||` and `!` build the tree and flatten associatively. Rendering happens once, at
request-build time, and picks the wire form appropriate to the node's position.

| Expression | Rendered |
|---|---|
| `\.done == false && \.priority > 3` | `done=eq.false&priority=gt.3` |
| `\.done == false \|\| \.priority > 3` | `or=(done.eq.false,priority.gt.3)` |
| `(\.done == false && \.priority > 3) \|\| \.pinned == true` | `or=(and(done.eq.false,priority.gt.3),pinned.eq.true)` |
| `!(\.done == false && \.priority > 3)` | `not.and=(done.eq.false,priority.gt.3)` |

Top-level AND flattens to separate query items, matching PostgREST's implicit AND and keeping URLs
close to today's snapshots. The third row is the payoff: today `or` takes pre-joined text, so
nesting an `and(…)` means writing it into the string by hand.

Filters are values, so they can be named, stored, passed and unit-tested without a client:

```swift
let overdue: PostgrestFilter<Todo> = \.dueDate < now && \.done == false
let mine: PostgrestFilter<Todo> = \.ownerID == userID

let rows = try await client.from(Todo.self)
  .select(TodoSummary.self)
  .where(overdue && (mine || \.isShared == true))
  .order(by: \.dueDate, .ascending)
  .limit(20)
  .execute()
```

Operators cover `==`, `!=`, `<`, `<=`, `>`, `>=` on KeyPaths and `&&`, `||`, `!` on filters.
Everything else is a static member, so leading-dot completion finds it:

```swift
.where(.in(\.status, ["active", "pending"]))
.where(.like(\.name, "Jo%"))
.where(.fts(\.content, "swift & ios", config: "english", type: .websearch))
.where(.contains(\.tags, ["swift"]))
.where(.rangeAdjacent(\.scheduled, someRange))
.where(.raw("cost::text.eq.10"))              // escape hatch
```

String construction produces the same type, so the untyped path is not a separate API:

```swift
.where(.eq("done", false) && .raw("priority.gt.3"))
```

Extending `KeyPath` with methods (`\.name.like("Jo%")`) was rejected: key-path expressions do not
accept call syntax, so every call site would need parentheses.

Escaping via `escapePostgRESTFilterValue` applies to every operand at render time, not only to list
operators. This is a behavior fix, not just a refactor.

### 4.4 Embedded scope

`referencedTable` is not a property of `or`. It is a scope prefix on the query-parameter key, and it
appears today on `or`, `order`, `limit` and `range`. Plain filters have no such parameter, so
scoping one means writing the prefix into the column name by hand (`.eq("comments.body", value: "x")`).

All four collapse into one construct:

```swift
try await client.from(Todo.self)
  .select(TodoWithComments.self)
  .where(\.done == false)
  .embedded(\.comments) {
    $0.where(\.approved == true || \.authorID == me)
      .order(by: \.createdAt, .descending)
      .limit(5)
  }
  .execute()

// select=…&done=eq.false
//   &comments.or=(approved.eq.true,author_id.eq.<me>)
//   &comments.order=created_at.desc.nullslast
//   &comments.limit=5
```

Untyped form: `.embedded("comments") { $0.where(.eq("approved", true)) }`.

Two properties worth stating:

- **An impossible query becomes unrepresentable.** PostgREST cannot OR a parent filter against an
  embedded one, because they are separate query parameters and therefore always ANDed. Keeping
  scope on the query rather than inside the filter tree means `\.done == false || (embedded filter)`
  cannot be written. The current string-based `or` offers no such protection.
- **Nesting composes.** PostgREST accepts dotted paths, so nested `embedded` calls render
  `comments.replies.limit=3`.

### 4.5 Select tiers

Four ways to select, each strictly less checked than the one above it.

```swift
// Whole row
.select()                                  // -> [Todo]

// Tier 1 — declared projection, fully checked
.select(TodoSummary.self)                  // -> [TodoSummary]

// Tier 2 — ad-hoc columns, caller names the decode type
.select(\.id, \.task, as: MyRow.self)      // -> [MyRow]

// Tier 3 — raw string, for casts, computed columns, and future PostgREST syntax
.select("id, task, cost::text, comments(*)")
```

Tier 1 is the main path. A projection declares its own columns, and the macro emits references that
the compiler checks against the row type:

```swift
@PostgrestSelection(from: Todo.self)
struct TodoSummary {
  let id: Int
  let task: String
  @PostgrestEmbed(\Todo.comments) let comments: [CommentBody]
}

// Expansion includes, among other things:
//   static let columnKeyPaths: [PartialKeyPath<Todo>] = [\Todo.id, \Todo.task]
// A typo in `task` is a compile error on that emitted line.
```

The macro cannot inspect `Todo`'s members — macros see syntax only. Cross-type checking works
because the macro *emits* references to `Todo`'s members, and the compiler checks the expansion.

Tier 1 gives plain dot-syntax (`rows[0].task`), working embeds, and a name for a shape reused across
call sites. Its cost is one declaration per distinct shape, which tiers 2 and 3 cover for one-off
queries.

Two alternatives were considered and rejected:

- **Parameter packs.** `select(\.id, \.task)` returning a projection read by KeyPath subscript. Loses
  dot-syntax on every partial query, gives poor diagnostics when one KeyPath is wrong, makes
  `Identifiable` and `Hashable` conformances awkward, and still needs a separate path for embeds.
- **A select result builder.** Swift cannot synthesize a nominal type from a result builder, so the
  result is still a tuple-like projection, with slow type-checking and worse diagnostics on top.

### 4.6 RPC

Functions get the same treatment as tables. A generated or hand-written descriptor carries the
name, the parameters and the result type:

```swift
@PostgrestFunction("search_todos")
struct SearchTodos: Codable, Sendable {
  typealias Result = [Todo]
  var keyword: String
}

let hits = try await client.rpc(SearchTodos(keyword: "groceries")).execute()

// Untyped fallback
let hits = try await client.rpc("search_todos", params: ["keyword": "groceries"])
  .select(as: [Todo].self).execute()
```

This removes today's clunky path for `get: true` / `head: true`, which encodes the params to
`Data`, decodes them back into `AnyJSON`, checks for `.object`, and throws a `PostgrestError` at
build time when the params are not a key-value type. With a descriptor the parameters are known to
be an object, so a read-only call is a modifier (`.readOnly()`) rather than a Boolean flag that can
fail.

### 4.7 Transport

```swift
public protocol PostgrestTransport: Sendable {
  func send(_ request: HTTPRequest, body: Data?) async throws -> (HTTPResponse, Data)
}
```

`HTTPTypes` only. This drops `HTTPURLResponse` and every `FoundationNetworking` import from the
public surface, and it lets the existing `Helpers/HTTP` interceptors compose — so the hand-rolled
retry loop in `execute` is deleted in favour of `RetryRequestInterceptor`. A `URLSessionTransport`
ships as the default. One transport instance is built per client, not per chain step.

### 4.8 Response, errors, auth

`execute()` returns the value directly. Metadata moves to a separate call, so the common case has
no `.value` suffix:

```swift
let todos = try await query.execute()               // [Todo]
let full  = try await query.executeWithResponse()   // value, count, status, headers, data
let total = try await query.count(.exact)           // Int
```

`count(_:)` replaces `execute(options: FetchOptions(head: true, count: .exact))`, so `FetchOptions`
disappears. `PostgrestResponse` becomes a `Sendable` struct over `HTTPResponse`, and it no longer
needs a `Void` instantiation for discarded bodies.

Errors become one enum with typed throws, distinguishing a PostgREST error from a decode failure
from a transport failure. Today those arrive as `PostgrestError`, a `DecodingError` and an
`HTTPError` with no common type.

Auth takes a token provider instead of mutating shared client headers:

```swift
public var accessToken: (@Sendable () async throws -> String?)?
```

This removes the race where a request in flight picks up a token change, and it matches how
`SupabaseClient` already sources tokens.

### 4.9 Surface removed

From `PostgrestFilterBuilder`, 16 forwarding methods: `equals`, `notEquals`, `greaterThan`,
`greaterThanOrEquals`, `lowerThan`, `lowerThanOrEquals`, `rangeLowerThan`, `rangeGreaterThan`,
`rangeGreaterThanOrEquals`, `rangeLowerThanOrEquals`, `fullTextSearch`, `plainToFullTextSearch`,
`phraseToFullTextSearch`, `webFullTextSearch`, `match(_:)`, `fts`. Operators and one
`.fts(_:_:config:type:)` cover all of them.

All of `Deprecated.swift`: the two deprecated initializers, `plfts`, `phfts`, `wfts`, the
`like(_:value:)` / `ilike(_:value:)` / `in(_:value:)` overloads, the `String`-format `explain`, and
the `URLQueryRepresentable` typealias.

`FetchOptions`, `FetchHandler`, `PostgrestReturningOptions` as a free-standing enum, and the
`queryValue` deprecation shim on `PostgrestFilterValue`.

### 4.10 Module layout

```
Sources/PostgREST/
  Client/PostgrestClient.swift
  Query/PostgrestTable.swift
  Query/PostgrestQuery.swift
  Query/PostgrestRawQuery.swift
  Query/PostgrestMutation.swift
  Query/PostgrestEmbeddedScope.swift
  Filters/PostgrestFilter.swift
  Filters/PostgrestFilter+Operators.swift
  Filters/PostgrestFilter+Render.swift
  Filters/PostgrestFilterValue.swift
  Rows/PostgrestRow.swift
  Rows/PostgrestProjection.swift
  Rows/AnyPostgrestRow.swift
  RPC/PostgrestFunction.swift
  Request/PostgrestRequest.swift          // pure request model plus rendering
  Transport/PostgrestTransport.swift
  Transport/URLSessionTransport.swift
  Response/PostgrestResponse.swift
  Errors/PostgrestQueryError.swift
  Legacy/                                 // today's 10 files, deprecated, untouched
Sources/PostgRESTMacros/                  // macro implementation
```

### 4.11 Testing

Value types make request building a pure function. `PostgrestRequest` is inspectable without
executing, so most of today's 3,384 lines of snapshot tests become direct assertions on a rendered
request. Filter rendering is tested as a pure tree-to-string function, with no client and no
network. A `PostgrestMockTransport` covers response handling, retry and error mapping.

## 5. Staging

| Stage | Delivers |
|---|---|
| 1 | Request model, transport, response, errors, filter tree, string-column API |
| 2 | `PostgrestRow`, typed tables, projections, `Insert` / `Update` variants |
| 3 | `@PostgrestTable` / `@PostgrestSelection` / `@PostgrestFunction` macros |
| 4 | Deprecate today's classes |
| 5 | Rewrite the postgres-meta Swift template (separate repository) |

Each stage gets its own implementation plan.

## 6. Migration

The old and new APIs coexist for one minor-version series. Existing code keeps compiling and emits
deprecation warnings.

For stage 4, today's implementation stays **in place and untouched**, marked deprecated, rather than
reimplemented over the new core. Value types cannot reproduce the old aliasing behavior, where two
chains branched off one builder mutate the same object. Some user code depends on that by accident.
Leaving the old code alone avoids silently changing it, and it deletes cleanly in the next major.
The cost is duplicated request-building logic for one release cycle.

`SupabaseClient.from(_:)`, `rpc(_:params:count:)` and `schema(_:)` in `Sources/Supabase` need new
overloads returning the new types. The deprecated `SupabaseClient.database` property is unaffected.

## 7. Open questions

**Naming.** `@PostgrestTable` is verbose, but a plain `@Table` collides with SwiftUI's `Table` and
with swift-structured-queries' `@Table` — both likely in the same projects. `PostgREST` is
`@_exported` from `Supabase`, so every public top-level name leaks into every file that imports
`Supabase`; names like `Table`, `Column`, `Filter` and `Query` are not viable unprefixed. Nesting
under a caseless `enum Postgrest` is now possible for protocols too (SE-0404), but it is unclear
whether macro declarations can nest. Decide before stage 1.

**Typed throws and `Sendable`.** Wrapping an arbitrary transport error inside a `Sendable` error
enum needs a boxing decision. `throws(PostgrestQueryError)` is only worth it if the payload stays
`Sendable` without losing the underlying error.

**Nested negation grammar.** The renderer assumes PostgREST accepts `not.or=(…)` at top level and
`not.and(…)` nested inside `or=(…)`. The top-level forms are documented. The nested form must be
verified against a running server before the renderer depends on it.

**`AsyncSequence` pagination.** `.pages(of:)` over `range` is cheap to add and useful, but it is not
required by anything today. Deferred until asked for.

**Generated projection types.** The generator currently emits one `Select` struct per table. Whether
it should also emit projections, and how a user would name them, is undecided. Not needed for
stages 1 to 4.
