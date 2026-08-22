# PostgREST v3 Stage 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship compile-time-checked table and column names for PostgREST queries, layered over
today's builders, plus two independent bug fixes to the current filter API.

**Architecture:** Three protocols land in `PostgREST`. A thin generic wrapper delegates to the
existing `PostgrestQueryBuilder` / `PostgrestFilterBuilder`, so no request-building logic is
rewritten. A separate opt-in `PostgrestMacros` module supplies the macros; `PostgREST` and `Supabase`
never depend on swift-syntax.

**Tech Stack:** Swift 6.1, SwiftPM, swift-syntax, swift-macro-testing, Swift Testing, Mocker.

**Spec:** [`docs/design/postgrest-v3.md`](./postgrest-v3.md) — §4.2 (protocols), §4.5 (selections),
§10 (this slice's scope). Read §10.2 before starting; it lists what is deliberately excluded.

## Global Constraints

- Swift 6.1 floor, `swift-tools-version:6.1`. Do not raise it.
- Platforms: iOS 16, macCatalyst 16, macOS 13, watchOS 9, tvOS 16.
- **Swift Testing only.** No `XCTest`, no `XCTestCase`. Explicit `@Suite` even when unadorned. Test
  functions drop the `test` prefix.
- Public types in `PostgREST` are prefixed `Postgrest`. Macro attributes in `PostgrestMacros` are
  bare (`@Table`, `@Column`) — this is the one deliberate exception, see spec §3.
- 2-space indentation. Run `./scripts/format.sh` before every commit.
- `./scripts/spell-check.sh` must exit 0 before every commit. Add legitimate technical terms to
  `dictionary.txt`.
- Every new public API needs a DocC comment.
- Conventional commits. `fix:` for Tasks 1–2, `feat:` for the rest.
- Slice 0 keeps today's `PostgrestResponse` and `.execute().value`. Do **not** change the response
  shape or the error type; those are stage 2.
- The wrapper types hold a reference to today's builder classes and therefore inherit their
  reference semantics. This is accepted and documented, not fixed here (spec §5).

---

## Task 1: Route a nil filter value to `is.null`

Today `Optional.none.rawValue` is `"NULL"` and `eq` interpolates it, emitting `col=eq.NULL`. Spec §9.3
proved that on a `text` column PostgREST matches the row whose value is the literal string `"NULL"`,
so this silently returns wrong rows. A generic optional overload keeps the nil knowledge that the
`any PostgrestFilterValue` existential erases.

**Files:**
- Create: `Tests/PostgRESTTests/QueryCapture.swift`
- Modify: `Sources/PostgREST/PostgrestFilterBuilder.swift`
- Test: `Tests/PostgRESTTests/PostgrestFilterBuilderTests.swift`

**Interfaces:**
- Produces: `QueryCapture` test helper with `client: PostgrestClient` and `query: String?`, used by
  every later task. `PostgrestFilterBuilder.eq<V: PostgrestFilterValue>(_:value: V?)` and the
  matching `neq`.

- [ ] **Step 1: Write the capture helper**

`Tests/PostgRESTTests/QueryCapture.swift`:

```swift
import ConcurrencyExtras
import Foundation
import PostgREST

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Captures the `URLRequest` a builder produces without a network round trip.
///
/// Slice 0 has no way to inspect a builder's request directly, so tests assert on what the
/// configured `fetch` handler receives.
struct QueryCapture {
  let client: PostgrestClient
  private let request = LockIsolated(URLRequest?.none)

  init(body: String = "[]") {
    let request = self.request
    client = PostgrestClient(
      url: URL(string: "https://example.supabase.co")!,
      headers: ["X-Client-Info": "postgrest-swift/test"],
      fetch: { received in
        request.setValue(received)
        let response = HTTPURLResponse(
          url: received.url!, statusCode: 200, httpVersion: nil,
          headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(body.utf8), response)
      }
    )
  }

  /// The percent-decoded query string of the captured request.
  var query: String? {
    request.value?.url?.query?.replacingOccurrences(of: "%22", with: "\"")
  }

  /// The HTTP method of the captured request.
  var httpMethod: String? { request.value?.httpMethod }

  /// The captured request body decoded as UTF-8.
  var bodyString: String? {
    request.value?.httpBody.map { String(decoding: $0, as: UTF8.self) }
  }

  /// A header field of the captured request.
  func header(_ name: String) -> String? {
    request.value?.value(forHTTPHeaderField: name)
  }
}
```

- [ ] **Step 2: Write the failing test**

Append to `Tests/PostgRESTTests/PostgrestFilterBuilderTests.swift`, inside the existing suite:

```swift
@Test
func eqWithNilOptionalUsesIsNull() async throws {
  let capture = QueryCapture()
  let value: String? = nil
  _ = try? await capture.client.from("messages").select().eq("message", value: value).execute()
  #expect(capture.query?.contains("message=is.null") == true)
  #expect(capture.query?.contains("eq.NULL") == false)
}

@Test
func eqWithPresentOptionalUsesEq() async throws {
  let capture = QueryCapture()
  let value: String? = "hello"
  _ = try? await capture.client.from("messages").select().eq("message", value: value).execute()
  #expect(capture.query?.contains("message=eq.hello") == true)
}

@Test
func neqWithNilOptionalUsesNotIsNull() async throws {
  let capture = QueryCapture()
  let value: String? = nil
  _ = try? await capture.client.from("messages").select().neq("message", value: value).execute()
  #expect(capture.query?.contains("message=not.is.null") == true)
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter PostgrestFilterBuilderTests`
Expected: `eqWithNilOptionalUsesIsNull` and `neqWithNilOptionalUsesNotIsNull` FAIL, because the
existing existential overload emits `eq.NULL`. `eqWithPresentOptionalUsesEq` passes already.

If `eqWithNilOptionalUsesIsNull` *passes* before you write the implementation, stop: it means the
existential overload is being selected and the new overload will not help. Report that instead of
proceeding.

- [ ] **Step 4: Add the overloads**

In `Sources/PostgREST/PostgrestFilterBuilder.swift`:

```swift
extension PostgrestFilterBuilder {
  /// Matches rows where `column` equals `value`, treating `nil` as a SQL `NULL` check.
  ///
  /// `column = NULL` is never true in SQL, so a `nil` value is sent as `is.null` rather than
  /// `eq.null`. Prefer this overload over ``is(_:value:)`` when the value is already optional.
  ///
  /// - Parameters:
  ///   - column: The column to filter on.
  ///   - value: The value to compare against, or `nil` to match SQL `NULL`.
  /// - Returns: The same builder instance so calls can be chained.
  @discardableResult
  public func eq<V: PostgrestFilterValue>(
    _ column: String,
    value: V?
  ) -> PostgrestFilterBuilder {
    guard let value else {
      mutableState.withValue {
        $0.request.query.append(URLQueryItem(name: column, value: "is.null"))
      }
      return self
    }
    return eq(column, value: value as any PostgrestFilterValue)
  }

  /// Matches rows where `column` is not equal to `value`, treating `nil` as a SQL `NOT NULL` check.
  ///
  /// - Parameters:
  ///   - column: The column to filter on.
  ///   - value: The value to compare against, or `nil` to match rows that are not SQL `NULL`.
  /// - Returns: The same builder instance so calls can be chained.
  @discardableResult
  public func neq<V: PostgrestFilterValue>(
    _ column: String,
    value: V?
  ) -> PostgrestFilterBuilder {
    guard let value else {
      mutableState.withValue {
        $0.request.query.append(URLQueryItem(name: column, value: "not.is.null"))
      }
      return self
    }
    return neq(column, value: value as any PostgrestFilterValue)
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter PostgrestFilterBuilderTests`
Expected: all three PASS, and no previously passing test in that suite regresses.

- [ ] **Step 6: Format, spell-check, commit**

```bash
./scripts/format.sh
./scripts/spell-check.sh
git add Sources/PostgREST/PostgrestFilterBuilder.swift \
        Tests/PostgRESTTests/PostgrestFilterBuilderTests.swift \
        Tests/PostgRESTTests/QueryCapture.swift
git commit -m "fix(postgrest): send is.null for a nil eq/neq filter value

col = NULL is never true in SQL. A nil optional rendered as eq.NULL, which
on a text column matches rows whose value is the literal string \"NULL\"
and misses actual nulls. A generic optional overload keeps the nil
knowledge the existential parameter erased."
```

**Deliberately out of scope:** `gt`, `gte`, `lt`, `lte` with a nil value. Routing those to `is.null`
would be wrong, and marking them unavailable would break code that compiles today. Record as a
follow-up decision; do not change them here.

---

## Task 2: Establish filter-value escaping — RESOLVED, no behavior change

> **Outcome (2026-08-22, SDK-1510).** The characterization step did its job and the task inverted:
> the asymmetry is correct, and Step 3 below would have been a regression. Spec §9.5 has the server
> measurement. Delivered instead: `Tests/PostgRESTTests/PostgrestFilterOperandEscapingTests.swift`
> pinning both halves of the rule, plus doc notes on `escapePostgRESTFilterValue`, `or` and `filter`.
>
> **What the server actually does.** A double quote in a top-level scalar operand is *data, not
> syntax* — a row storing literally `"quoted"` is what `txt=eq.%22quoted%22` returns. So `eq."a,b"`
> matches nothing where `eq.a,b` matches correctly, and 22 awkward scalar values (`a,b`, `a"b`,
> `a\b`, `a(b)c`, `a.b`, `a&b`, `a b`, `(1,2)`, `{a,b}`, `a->>b`, …) all round-trip fine unescaped.
> The rule is **positional**: escape only where the operand sits inside a delimited list. `in` and
> `notIn` are the only two builders in that position, so two out of thirty is the right number.
> Array and range literals escape one layer down, per element, via `postgrestArrayElement`; quoting
> the whole literal gives `22P02 malformed array literal` / `malformed range literal`.
>
> **The one real find.** In `or`, the comma *is* structural — `or=(txt.eq.a,b)` is a 400 `PGRST100`.
> That is the only place a caller must quote by hand, and it was undocumented.
>
> The steps below are kept as written, for the record. Do not execute Step 3.

`escapePostgRESTFilterValue` is called only by `in` and `notIn`. What breaks for the other operators
is unverified, so this task writes characterization tests first and only then changes behavior.

**Files:**
- Modify: `Sources/PostgREST/PostgrestFilterBuilder.swift`
- Test: `Tests/PostgRESTTests/PostgrestFilterBuilderTests.swift`

**Interfaces:**
- Consumes: `QueryCapture` from Task 1.

- [x] **Step 1: Write characterization tests that record current behavior**

```swift
@Test
func eqEscapesReservedCharacters() async throws {
  let capture = QueryCapture()
  _ = try? await capture.client.from("messages")
    .select().eq("message", value: "a,b").execute()
  #expect(capture.query?.contains("message=eq.\"a,b\"") == true)
}

@Test
func eqEscapesEmbeddedQuote() async throws {
  let capture = QueryCapture()
  _ = try? await capture.client.from("messages")
    .select().eq("message", value: "say \"hi\"").execute()
  #expect(capture.query?.contains("\\\"") == true)
}

@Test
func eqLeavesPlainValueUnquoted() async throws {
  let capture = QueryCapture()
  _ = try? await capture.client.from("messages")
    .select().eq("message", value: "hello").execute()
  #expect(capture.query?.contains("message=eq.hello") == true)
}
```

- [x] **Step 2: Run them and record what actually happens**

Run: `swift test --filter PostgrestFilterBuilderTests`
Expected: the first two FAIL (no escaping today), the third PASSES.

Observed: exactly that. `eq.a,b`, `eq.a"b`, `eq.plain`, `match.@supabase\.io$` all raw;
`in.("a,b")` and `cs.{"a,b",c}` correctly escaped.

Write the observed failure output into the commit message in Step 5. If the first two *pass*,
escaping is already applied somewhere and this task is unnecessary — stop and report.

> The stop-condition as written was too narrow. It only caught "escaping already applied", not
> "escaping must not be applied". The test assertions above *assume the conclusion* — they assert
> `eq."a,b"` is desirable rather than measuring whether the server accepts it. A characterization
> test should record what the code emits; deciding whether that is right needs the server. Adding a
> Step 2b (ask the server) is what turned this task around.

- [ ] ~~**Step 3: Apply escaping in the shared render path**~~ — **do not do this. It is a regression.**

The operators build their value with string interpolation. Add one private helper and route the
single-value operators through it. In `Sources/PostgREST/PostgrestFilterBuilder.swift`:

```swift
extension PostgrestFilterBuilder {
  /// Renders a filter operand, quoting it when it contains characters that carry structural
  /// meaning in a PostgREST filter.
  fileprivate static func operand(_ value: any PostgrestFilterValue) -> String {
    escapePostgRESTFilterValue(value.rawValue)
  }
}
```

Then change each single-value operator's body to use it. For `eq`:

```swift
$0.request.query.append(
  URLQueryItem(name: column, value: "eq.\(Self.operand(value))")
)
```

Apply the identical change to `neq`, `gt`, `gte`, `lt`, `lte`, `like`, `ilike`, `match`, `imatch`,
`isDistinct`, `contains`, `containedBy`, `overlaps`, and the four range operators (`rangeLt`,
`rangeGt`, `rangeGte`, `rangeLte`, `rangeAdjacent`). Do **not** change `is` (its operands are the
literals `true`, `false`, `null`), `in`/`notIn` (already escaped), `or`, `filter`, or the full-text
search operators, whose values are `tsquery` expressions where quoting changes meaning.

- [x] **Step 4: Run the full PostgREST suite**

Run: `swift test --filter PostgRESTTests`
Expected: the three new tests PASS. Snapshot tests in `BuildURLRequestTests` may now differ — inspect
each diff and confirm it is an intended escaping change before re-recording. Do not blanket
re-record.

Observed: 1232 tests in 124 suites pass. No snapshot differed, because no behavior changed — which is
itself the confirmation that Step 3 was not applied.

- [x] **Step 5: Format, spell-check, commit**

```bash
./scripts/format.sh
./scripts/spell-check.sh
git add Sources/Helpers/PostgRESTFilterValue.swift \
        Sources/PostgREST/PostgrestFilterBuilder.swift \
        Tests/PostgRESTTests/PostgrestFilterOperandEscapingTests.swift
git commit -m "test(postgrest): pin filter-operand escaping, and why it is asymmetric

escapePostgRESTFilterValue is called only by in/notIn, which reads like an
oversight and was filed as one. Measured against PostgREST 14.15: it is
correct. A top-level scalar operand runs to the end of the query-parameter
value, so nothing in it is structural, and quoting it changes what is
compared rather than delimiting it. Escaping belongs only where the operand
sits inside a delimited list. No behavior change; the rule is now pinned by
tests and documented at all three call sites."
```

---

## Task 3: The three protocols

Spec §4.2. These land in `PostgREST` from the first commit even though nothing needs them there until
stage 2 — they are forty lines, and putting them in the macro module is what made PR #1036
unmergeable.

**Files:**
- Create: `Sources/PostgREST/Relations/PostgrestRelation.swift`
- Test: `Tests/PostgRESTTests/PostgrestRelationTests.swift`

**Interfaces:**
- Produces: `PostgrestSelection` (`static var selectString: String`), `PostgrestRelation`
  (`relationName`, `schema`, `columnName<V>(for:)`), `PostgrestWritableRelation`
  (`associatedtype Insert`, `associatedtype Update`). Every later task constrains against these.

- [ ] **Step 1: Write the failing test**

`Tests/PostgRESTTests/PostgrestRelationTests.swift`:

```swift
import Testing

@testable import PostgREST

@Suite
struct PostgrestRelationTests {
  struct Todo: PostgrestWritableRelation {
    static let relationName = "todos"
    static let schema = "public"
    static let selectString = "*"

    var id: Int
    var task: String
    var isDone: Bool

    static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String {
      switch keyPath {
      case \Self.id: "id"
      case \Self.task: "task"
      case \Self.isDone: "is_done"
      default: fatalError("unmapped key path")
      }
    }

    struct Insert: Encodable, Sendable {
      var task: String
      var isDone: Bool?
    }
    struct Update: Encodable, Sendable {
      var task: String?
      var isDone: Bool?
    }
  }

  @Test
  func columnNameMapsKeyPathToDatabaseColumn() {
    #expect(Todo.columnName(for: \.id) == "id")
    #expect(Todo.columnName(for: \.isDone) == "is_done")
  }

  @Test
  func aRelationIsAlsoASelection() {
    func selectString(of type: some PostgrestSelection.Type) -> String { type.selectString }
    #expect(selectString(of: Todo.self) == "*")
  }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter PostgrestRelationTests`
Expected: FAIL to compile — `cannot find type 'PostgrestWritableRelation' in scope`.

- [ ] **Step 3: Write the protocols**

`Sources/PostgREST/Relations/PostgrestRelation.swift`:

```swift
//
//  PostgrestRelation.swift
//  PostgREST
//
//  Created by Guilherme Souza on 11/08/26.
//

/// A shape that can be selected from a relation.
///
/// Conformance is normally synthesized by the `@Table` or `@SelectionOf` macro in the
/// `PostgrestMacros` module, or emitted by the schema generator. Hand-written conformances are
/// supported and are the escape hatch when neither fits.
public protocol PostgrestSelection: Decodable, Sendable {
  /// The PostgREST `select` expression for this shape, for example `"id,task"`.
  static var selectString: String { get }
}

/// A queryable source of rows: a table, a view, or a materialized view.
///
/// "Relation" is Postgres's own term for that family. Selecting a whole row is the degenerate
/// selection, which is why this refines ``PostgrestSelection``.
public protocol PostgrestRelation: PostgrestSelection {
  /// The relation's name as PostgREST addresses it.
  static var relationName: String { get }

  /// The Postgres schema the relation belongs to.
  static var schema: String { get }

  /// The database column name backing a property.
  ///
  /// - Parameter keyPath: A key path to one of this type's stored properties.
  /// - Returns: The column name PostgREST expects in a query string.
  static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String
}

/// A relation the database accepts writes for: a table, or a view Postgres reports as updatable.
///
/// `Insert` and `Update` have no defaults on purpose. Defaulting them to `Self` would mean sending
/// the primary key on insert and requiring every column on update.
public protocol PostgrestWritableRelation: PostgrestRelation {
  /// The shape accepted by an insert: primary keys excluded, defaulted and nullable columns optional.
  associatedtype Insert: Encodable & Sendable

  /// The shape accepted by an update: every column optional.
  associatedtype Update: Encodable & Sendable
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `swift test --filter PostgrestRelationTests`
Expected: PASS, 2 tests.

- [ ] **Step 5: Format, spell-check, commit**

```bash
./scripts/format.sh
./scripts/spell-check.sh
git add Sources/PostgREST/Relations/ Tests/PostgRESTTests/PostgrestRelationTests.swift
git commit -m "feat(postgrest): add the relation and selection protocols

Tables, views and materialized views are relations; only some are
writable. Writes hang off the writable refinement so a read-only view
cannot be written at compile time."
```

---

## Task 4: `from(_ type:)` and whole-row select

**Files:**
- Create: `Sources/PostgREST/Query/PostgrestTypedSource.swift`
- Create: `Sources/PostgREST/Query/PostgrestTypedQuery.swift`
- Test: `Tests/PostgRESTTests/PostgrestTypedSourceTests.swift`

**Interfaces:**
- Consumes: the three protocols from Task 3, `QueryCapture` from Task 1.
- Produces: `PostgrestClient.from<R: PostgrestRelation>(_ relation: R.Type) -> PostgrestTypedSource<R>`;
  `PostgrestTypedSource<R>.select() -> PostgrestTypedQuery<R, [R]>`;
  `PostgrestTypedQuery<R, Output>.execute() async throws -> PostgrestResponse<Output>` with a
  `builder: PostgrestFilterBuilder` stored property that Tasks 5 and 6 extend.

- [ ] **Step 1: Write the failing test**

`Tests/PostgRESTTests/PostgrestTypedSourceTests.swift`:

```swift
import Foundation
import Testing

@testable import PostgREST

@Suite
struct PostgrestTypedSourceTests {
  struct Todo: PostgrestRelation {
    static let relationName = "todos"
    static let schema = "public"
    static let selectString = "*"

    var id: Int
    var task: String

    static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String {
      switch keyPath {
      case \Self.id: "id"
      case \Self.task: "task"
      default: fatalError("unmapped key path")
      }
    }
  }

  @Test
  func fromUsesTheRelationName() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self).select().execute()
    #expect(capture.query?.contains("select=*") == true)
  }

  @Test
  func selectDecodesIntoTheRelationType() async throws {
    let capture = QueryCapture(body: #"[{"id":1,"task":"buy milk"}]"#)
    let todos = try await capture.client.from(Todo.self).select().execute().value
    #expect(todos.count == 1)
    #expect(todos.first?.task == "buy milk")
  }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter PostgrestTypedSourceTests`
Expected: FAIL to compile — `no exact matches in call to instance method 'from'`.

- [ ] **Step 3: Write the source wrapper**

`Sources/PostgREST/Query/PostgrestTypedSource.swift`:

```swift
//
//  PostgrestTypedSource.swift
//  PostgREST
//
//  Created by Guilherme Souza on 11/08/26.
//

extension PostgrestClient {
  /// Returns a typed source for a relation, so column and relation names are checked by the
  /// compiler instead of being spelled as strings.
  ///
  /// ```swift
  /// let todos = try await client.from(Todo.self).select().execute().value
  /// ```
  ///
  /// - Parameter relation: The relation type to query.
  /// - Returns: A ``PostgrestTypedSource`` for that relation.
  public func from<R: PostgrestRelation>(_ relation: R.Type) -> PostgrestTypedSource<R> {
    PostgrestTypedSource(builder: from(R.relationName))
  }
}

/// A relation that has been chosen but for which no operation has been picked yet.
///
/// It is called a *source* rather than a table because it may be a view, and rather than a query
/// because no operation has been chosen. Obtain one from ``PostgrestClient/from(_:)-swift.method``.
///
/// > Note: This type wraps the string-based builders and therefore shares their reference
/// > semantics. Do not branch two chains off one value.
public struct PostgrestTypedSource<R: PostgrestRelation> {
  let builder: PostgrestQueryBuilder

  /// Selects every column of the relation.
  ///
  /// - Returns: A ``PostgrestTypedQuery`` decoding into `[R]`.
  public func select() -> PostgrestTypedQuery<R, [R]> {
    PostgrestTypedQuery(builder: builder.select(R.selectString))
  }
}
```

`Sources/PostgREST/Query/PostgrestTypedQuery.swift`:

```swift
//
//  PostgrestTypedQuery.swift
//  PostgREST
//
//  Created by Guilherme Souza on 11/08/26.
//

/// A read request against a relation, with filters and modifiers applied by key path.
///
/// > Note: This type wraps the string-based builders and therefore shares their reference
/// > semantics. Do not branch two chains off one value.
public struct PostgrestTypedQuery<R: PostgrestRelation, Output: Decodable & Sendable> {
  public let builder: PostgrestFilterBuilder

  public init(builder: PostgrestFilterBuilder) {
    self.builder = builder
  }

  /// Sends the request and decodes the response.
  ///
  /// - Returns: A ``PostgrestResponse`` whose `value` is the decoded `Output`.
  @discardableResult
  public func execute() async throws -> PostgrestResponse<Output> {
    try await builder.execute()
  }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `swift test --filter PostgrestTypedSourceTests`
Expected: PASS, 2 tests.

- [ ] **Step 5: Format, spell-check, commit**

```bash
./scripts/format.sh
./scripts/spell-check.sh
git add Sources/PostgREST/Query/ Tests/PostgRESTTests/PostgrestTypedSourceTests.swift
git commit -m "feat(postgrest): add from(_ type:) and a typed whole-row select

Wraps the existing builders rather than reimplementing request building,
so the typed surface can ship before the value-typed core."
```

---

## Task 5: Key-path filters and modifiers

**Files:**
- Create: `Sources/PostgREST/Query/PostgrestTypedQuery+Filters.swift`
- Test: `Tests/PostgRESTTests/PostgrestTypedQueryFilterTests.swift`

**Interfaces:**
- Consumes: `PostgrestTypedQuery` from Task 4.
- Produces: `PostgrestKeyPathFilterable`, and on it `eq`, `neq`, `gt`, `gte`, `lt`, `lte`, `in`,
  `isNull`, `isNotNull`, `order`, `limit`, each returning `Self`. Task 6's mutation type conforms to
  the same protocol and inherits all of them, so this set is written exactly once.

- [ ] **Step 1: Write the failing test**

`Tests/PostgRESTTests/PostgrestTypedQueryFilterTests.swift`:

```swift
import Foundation
import Testing

@testable import PostgREST

@Suite
struct PostgrestTypedQueryFilterTests {
  struct Todo: PostgrestRelation {
    static let relationName = "todos"
    static let schema = "public"
    static let selectString = "*"

    var id: Int
    var task: String
    var isDone: Bool
    var dueDate: Date?

    static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String {
      switch keyPath {
      case \Self.id: "id"
      case \Self.task: "task"
      case \Self.isDone: "is_done"
      case \Self.dueDate: "due_date"
      default: fatalError("unmapped key path")
      }
    }
  }

  @Test
  func eqUsesTheMappedColumnName() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self).select().eq(\.isDone, false).execute()
    #expect(capture.query?.contains("is_done=eq.false") == true)
  }

  @Test
  func comparisonOperatorsRenderTheirPrefix() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self).select().gt(\.id, 10).lte(\.id, 20).execute()
    #expect(capture.query?.contains("id=gt.10") == true)
    #expect(capture.query?.contains("id=lte.20") == true)
  }

  @Test
  func inRendersAParenthesisedList() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self).select().in(\.task, ["a", "b"]).execute()
    #expect(capture.query?.contains("task=in.(a,b)") == true)
  }

  @Test
  func isNullAndIsNotNullRenderCorrectly() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self).select().isNull(\.dueDate).execute()
    #expect(capture.query?.contains("due_date=is.null") == true)

    let other = QueryCapture()
    _ = try await other.client.from(Todo.self).select().isNotNull(\.dueDate).execute()
    #expect(other.query?.contains("due_date=not.is.null") == true)
  }

  @Test
  func orderAndLimitUseTheMappedColumnName() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self)
      .select().order(\.dueDate, ascending: false).limit(5).execute()
    #expect(capture.query?.contains("order=due_date.desc") == true)
    #expect(capture.query?.contains("limit=5") == true)
  }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter PostgrestTypedQueryFilterTests`
Expected: FAIL to compile — `value of type 'PostgrestTypedQuery<...>' has no member 'eq'`.

- [ ] **Step 3: Write the filter extension**

`Sources/PostgREST/Query/PostgrestTypedQuery+Filters.swift`:

```swift
//
//  PostgrestTypedQuery+Filters.swift
//  PostgREST
//
//  Created by Guilherme Souza on 11/08/26.
//

/// A wrapper that scopes a request by key path.
///
/// Both ``PostgrestTypedQuery`` and ``PostgrestTypedMutation`` conform, so the key-path filter set is
/// declared once. You do not conform your own types to this.
public protocol PostgrestKeyPathFilterable {
  /// The relation whose key paths this wrapper accepts.
  associatedtype Relation: PostgrestRelation

  /// The underlying string-based builder.
  var builder: PostgrestFilterBuilder { get }

  /// Wraps a builder, preserving the wrapper's type.
  init(builder: PostgrestFilterBuilder)
}

extension PostgrestTypedQuery: PostgrestKeyPathFilterable {
  public typealias Relation = R
}

extension PostgrestKeyPathFilterable {
  /// Matches rows where the column at `column` equals `value`.
  public func eq<V: PostgrestFilterValue>(_ column: KeyPath<Relation, V>, _ value: V) -> Self {
    Self(builder: builder.eq(Relation.columnName(for: column), value: value))
  }

  /// Matches rows where the column at `column` is not equal to `value`.
  public func neq<V: PostgrestFilterValue>(_ column: KeyPath<Relation, V>, _ value: V) -> Self {
    Self(builder: builder.neq(Relation.columnName(for: column), value: value))
  }

  /// Matches rows where the column at `column` is greater than `value`.
  public func gt<V: PostgrestFilterValue>(_ column: KeyPath<Relation, V>, _ value: V) -> Self {
    Self(builder: builder.gt(Relation.columnName(for: column), value: value))
  }

  /// Matches rows where the column at `column` is greater than or equal to `value`.
  public func gte<V: PostgrestFilterValue>(_ column: KeyPath<Relation, V>, _ value: V) -> Self {
    Self(builder: builder.gte(Relation.columnName(for: column), value: value))
  }

  /// Matches rows where the column at `column` is less than `value`.
  public func lt<V: PostgrestFilterValue>(_ column: KeyPath<Relation, V>, _ value: V) -> Self {
    Self(builder: builder.lt(Relation.columnName(for: column), value: value))
  }

  /// Matches rows where the column at `column` is less than or equal to `value`.
  public func lte<V: PostgrestFilterValue>(_ column: KeyPath<Relation, V>, _ value: V) -> Self {
    Self(builder: builder.lte(Relation.columnName(for: column), value: value))
  }

  /// Matches rows where the column at `column` is one of `values`.
  public func `in`<V: PostgrestFilterValue>(_ column: KeyPath<Relation, V>, _ values: [V]) -> Self {
    Self(builder: builder.in(Relation.columnName(for: column), values: values))
  }

  /// Matches rows where the optional column at `column` is SQL `NULL`.
  public func isNull<V>(_ column: KeyPath<Relation, V?>) -> Self {
    Self(builder: builder.filter(Relation.columnName(for: column), operator: "is", value: "null"))
  }

  /// Matches rows where the optional column at `column` is not SQL `NULL`.
  public func isNotNull<V>(_ column: KeyPath<Relation, V?>) -> Self {
    Self(builder: builder.filter(Relation.columnName(for: column), operator: "not.is", value: "null"))
  }

  /// Sorts the result by the column at `column`.
  public func order<V>(
    _ column: KeyPath<Relation, V>,
    ascending: Bool = true,
    nullsFirst: Bool = false
  ) -> Self {
    Self(
      builder: builder.order(
        Relation.columnName(for: column), ascending: ascending, nullsFirst: nullsFirst
      ) as! PostgrestFilterBuilder
    )
  }

  /// Limits the number of rows returned.
  public func limit(_ count: Int) -> Self {
    Self(builder: builder.limit(count) as! PostgrestFilterBuilder)
  }
}
```

> **Note on the two force casts.** `order` and `limit` are declared on
> `PostgrestTransformBuilder` and return that type, even though the receiver is a
> `PostgrestFilterBuilder`. Since `PostgrestFilterBuilder` subclasses it and the methods return
> `self`, the cast always succeeds. If the compiler rejects `as!` here, use
> `builder.order(...) as? PostgrestFilterBuilder ?? builder` instead and note it in the PR — stage 2
> removes the hierarchy that forces this.

- [ ] **Step 4: Run it to verify it passes**

Run: `swift test --filter PostgrestTypedQueryFilterTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Format, spell-check, commit**

```bash
./scripts/format.sh
./scripts/spell-check.sh
git add Sources/PostgREST/Query/PostgrestTypedQuery+Filters.swift \
        Tests/PostgRESTTests/PostgrestTypedQueryFilterTests.swift
git commit -m "feat(postgrest): add key-path filters and modifiers to the typed query

A mistyped column is now a compile error instead of a runtime 400."
```

---

## Task 6: Writes, gated on the writable refinement

The four writes hang off a constrained extension, so `client.from(ActiveTodo.self).insert(…)` is *no
such member* rather than a runtime 405.

**Files:**
- Create: `Sources/PostgREST/Query/PostgrestTypedMutation.swift`
- Test: `Tests/PostgRESTTests/PostgrestTypedMutationTests.swift`

**Interfaces:**
- Consumes: `PostgrestTypedSource`, `PostgrestKeyPathFilterable` from Tasks 4 and 5.
- Produces: `PostgrestTypedMutation<R>` conforming to `PostgrestKeyPathFilterable`, with
  `execute() async throws -> PostgrestResponse<Void>` and `returning() -> PostgrestTypedQuery<R, [R]>`.
  On `PostgrestTypedSource where R: PostgrestWritableRelation`: `insert`, `upsert`, `update`, `delete`.

- [ ] **Step 1: Write the failing test**

`Tests/PostgRESTTests/PostgrestTypedMutationTests.swift`:

```swift
import Foundation
import Testing

@testable import PostgREST

@Suite
struct PostgrestTypedMutationTests {
  struct Todo: PostgrestWritableRelation {
    static let relationName = "todos"
    static let schema = "public"
    static let selectString = "*"

    var id: Int
    var task: String
    var isDone: Bool

    static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String {
      switch keyPath {
      case \Self.id: "id"
      case \Self.task: "task"
      case \Self.isDone: "is_done"
      default: fatalError("unmapped key path")
      }
    }

    struct Insert: Encodable, Sendable {
      var task: String
      var isDone: Bool?
    }
    struct Update: Encodable, Sendable {
      var task: String?
      var isDone: Bool?
    }
  }

  /// A view: conforms to `PostgrestRelation` only, so the writes must not be offered.
  struct ActiveTodo: PostgrestRelation {
    static let relationName = "active_todos"
    static let schema = "public"
    static let selectString = "*"

    var id: Int

    static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String {
      switch keyPath {
      case \Self.id: "id"
      default: fatalError("unmapped key path")
      }
    }
  }

  @Test
  func insertSendsTheInsertShape() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self)
      .insert(Todo.Insert(task: "buy milk", isDone: nil)).execute()
    #expect(capture.httpMethod == "POST")
    // The Insert shape excludes the primary key, so `id` must not appear in the body.
    #expect(capture.bodyString?.contains("\"task\":\"buy milk\"") == true)
    #expect(capture.bodyString?.contains("\"id\"") == false)
  }

  @Test
  func preferHeaderIsUnambiguousWhenReturningRows() async throws {
    let capture = QueryCapture(body: #"[{"id":1,"task":"buy milk","is_done":false}]"#)
    _ = try await capture.client.from(Todo.self)
      .insert(Todo.Insert(task: "buy milk", isDone: nil)).returning().execute()
    let prefer = capture.header("Prefer") ?? ""
    #expect(prefer.contains("return=representation"))
    #expect(prefer.contains("return=minimal") == false)
  }

  @Test
  func updateScopesByKeyPath() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self)
      .update(Todo.Update(task: "done", isDone: true)).eq(\.id, 1).execute()
    #expect(capture.query?.contains("id=eq.1") == true)
  }

  @Test
  func deleteScopesByKeyPath() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self).delete().eq(\.id, 1).execute()
    #expect(capture.query?.contains("id=eq.1") == true)
  }

  @Test
  func returningDecodesRows() async throws {
    let capture = QueryCapture(body: #"[{"id":1,"task":"buy milk","is_done":false}]"#)
    let rows = try await capture.client.from(Todo.self)
      .insert(Todo.Insert(task: "buy milk", isDone: nil)).returning().execute().value
    #expect(rows.first?.task == "buy milk")
  }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter PostgrestTypedMutationTests`
Expected: FAIL to compile — `value of type 'PostgrestTypedSource<Todo>' has no member 'insert'`.

- [ ] **Step 3: Write the mutation type and the constrained writes**

`Sources/PostgREST/Query/PostgrestTypedMutation.swift`:

```swift
//
//  PostgrestTypedMutation.swift
//  PostgREST
//
//  Created by Guilherme Souza on 11/08/26.
//

/// A write request against a writable relation.
///
/// Obtain one from `insert`, `upsert`, `update` or `delete` on a ``PostgrestTypedSource``. Those
/// methods exist only where the relation conforms to ``PostgrestWritableRelation``, so a read-only
/// view cannot be written.
///
/// > Note: This type wraps the string-based builders and therefore shares their reference
/// > semantics. Do not branch two chains off one value.
public struct PostgrestTypedMutation<R: PostgrestWritableRelation>: PostgrestKeyPathFilterable {
  public typealias Relation = R

  public let builder: PostgrestFilterBuilder

  public init(builder: PostgrestFilterBuilder) {
    self.builder = builder
  }

  /// Requests the affected rows back, decoded as `[R]`.
  ///
  /// This replaces the `Prefer` header rather than appending to it. The write methods set
  /// `return=minimal` so a plain ``execute()`` does not transfer rows, and appending would leave
  /// `Prefer: return=minimal,return=representation`, which is contradictory. `return=representation`
  /// alone returns every column, so no `select` parameter is needed.
  ///
  /// > Note: Because this replaces the whole header, do not combine it with any other `Prefer`
  /// > preference on a mutation. Slice 0 sets none.
  ///
  /// - Returns: A ``PostgrestTypedQuery`` decoding into `[R]`.
  public func returning() -> PostgrestTypedQuery<R, [R]> {
    PostgrestTypedQuery(
      builder: builder.setHeader(name: "Prefer", value: "return=representation")
    )
  }

  /// Sends the request, discarding the response body.
  @discardableResult
  public func execute() async throws -> PostgrestResponse<Void> {
    try await builder.execute()
  }
}

extension PostgrestTypedSource where R: PostgrestWritableRelation {
  /// Inserts a row.
  ///
  /// - Parameter values: The row to insert, in the relation's `Insert` shape. Primary keys and
  ///   defaulted columns are absent or optional there.
  public func insert(_ values: R.Insert) throws -> PostgrestTypedMutation<R> {
    PostgrestTypedMutation(builder: try builder.insert(values, returning: .minimal))
  }

  /// Inserts rows, updating any that conflict.
  ///
  /// - Parameters:
  ///   - values: The rows to upsert.
  ///   - onConflict: Comma-separated unique columns that determine a duplicate. Defaults to the
  ///     relation's primary key.
  public func upsert(
    _ values: R.Insert,
    onConflict: String? = nil
  ) throws -> PostgrestTypedMutation<R> {
    PostgrestTypedMutation(
      builder: try builder.upsert(values, onConflict: onConflict, returning: .minimal)
    )
  }

  /// Updates the rows matched by the filters applied to the returned value.
  ///
  /// > Important: With no filter this updates every row in the relation.
  public func update(_ values: R.Update) throws -> PostgrestTypedMutation<R> {
    PostgrestTypedMutation(builder: try builder.update(values, returning: .minimal))
  }

  /// Deletes the rows matched by the filters applied to the returned value.
  ///
  /// > Important: With no filter this deletes every row in the relation.
  public func delete() -> PostgrestTypedMutation<R> {
    PostgrestTypedMutation(builder: builder.delete(returning: .minimal))
  }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `swift test --filter PostgrestTypedMutationTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Verify the read-only gate by hand**

Add this line temporarily inside `insertSendsTheInsertShape`, build, and confirm the compiler rejects
it, then delete the line:

```swift
_ = try capture.client.from(ActiveTodo.self).insert(Todo.Insert(task: "x", isDone: nil))
```

Run: `swift build --target PostgRESTTests 2>&1 | grep "has no member 'insert'"`
Expected: one match. This is a manual check because Swift Testing cannot assert that code fails to
compile. Record the result in the PR description.

- [ ] **Step 6: Format, spell-check, commit**

```bash
./scripts/format.sh
./scripts/spell-check.sh
git add Sources/PostgREST/Query/PostgrestTypedMutation.swift \
        Tests/PostgRESTTests/PostgrestTypedMutationTests.swift
git commit -m "feat(postgrest): add typed writes gated on the writable refinement

insert/upsert/update/delete live on a constrained extension, so writing to
a read-only view is a compile error rather than a runtime 405."
```

---

## Task 7: Macro targets

No macro infrastructure exists in this package yet. This task adds it and proves the boundary before
any macro logic is written.

**Files:**
- Modify: `Package.swift`
- Create: `Sources/PostgrestMacrosPlugin/Plugin.swift`
- Create: `Sources/PostgrestMacros/Macros.swift`
- Create: `Tests/PostgrestMacrosTests/PluginTests.swift`

**Interfaces:**
- Produces: the `PostgrestMacrosPlugin` compiler-plugin target, the `PostgrestMacros` library target
  depending on `PostgREST`, and the `PostgrestMacrosTests` test target with `MacroTesting`.

- [ ] **Step 1: Add the targets and dependencies**

In `Package.swift`, add to `dependencies`:

```swift
.package(url: "https://github.com/swiftlang/swift-syntax", "600.0.0"..<"605.0.0"),
.package(url: "https://github.com/pointfreeco/swift-macro-testing", from: "0.6.0"),
```

Add `import CompilerPluginSupport` at the top, next to `import PackageDescription`. Add to
`products`:

```swift
.library(name: "PostgrestMacros", targets: ["PostgrestMacros"]),
```

Add to `targets`:

```swift
.macro(
  name: "PostgrestMacrosPlugin",
  dependencies: [
    .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
    .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
  ]
),
.target(
  name: "PostgrestMacros",
  dependencies: [
    "PostgrestMacrosPlugin",
    "PostgREST",
  ]
),
.testTarget(
  name: "PostgrestMacrosTests",
  dependencies: [
    .product(name: "MacroTesting", package: "swift-macro-testing"),
    "PostgrestMacros",
    "PostgrestMacrosPlugin",
  ]
),
```

Finally, exempt the plugin target from the import-visibility upcoming features. Find the loop near the
bottom of the file that appends `swiftSettings` per target and guard it:

```swift
// The compiler-plugin target must declare its macro types `public` to satisfy SwiftSyntax's
// `CompilerPlugin` protocol, which `InternalImportsByDefault` rejects — a public conformance to a
// protocol from an internally-imported module is an error. Plugins run at build time and ship no
// distributable API, so these features gain nothing there.
if target.name != "PostgrestMacrosPlugin" {
  // existing appends of InternalImportsByDefault / MemberImportVisibility stay here
}
```

- [ ] **Step 2: Write the plugin entry point**

`Sources/PostgrestMacrosPlugin/Plugin.swift`:

```swift
import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct PostgrestMacrosPlugin: CompilerPlugin {
  let providingMacros: [any Macro.Type] = []
}
```

`Sources/PostgrestMacros/Macros.swift`:

```swift
//
//  Macros.swift
//  PostgrestMacros
//
//  Created by Guilherme Souza on 11/08/26.
//

@_exported import PostgREST
```

- [ ] **Step 3: Write the boundary test**

`Tests/PostgrestMacrosTests/PluginTests.swift`:

```swift
import Testing

@testable import PostgrestMacros

@Suite
struct PluginTests {
  @Test
  func macroModuleReExportsPostgREST() {
    // Compiles only if PostgrestMacros re-exports PostgREST, which is what lets a user write a
    // single `import PostgrestMacros`.
    #expect(PostgrestClient.Configuration.defaultHeaders["X-Client-Info"] != nil)
  }
}
```

- [ ] **Step 4: Verify resolution and the build**

```bash
swift package resolve
swift build 2>&1 | tail -5
swift test --filter PostgrestMacrosTests
```

Expected: resolution succeeds and prints a swift-syntax version in the 600–604 range; the build
succeeds; the one test passes. If resolution fails because no version in that range is compatible
with the toolchain, widen the upper bound one major at a time and record the resolved version in the
commit message — do not lower the package's tools-version.

- [ ] **Step 5: Prove PostgREST does not depend on swift-syntax**

```bash
swift package show-dependencies --format json > /tmp/deps.json
python3 - <<'PY'
import json
d = json.load(open("/tmp/deps.json"))
# Fails loudly if PostgREST's own dependency closure gains swift-syntax.
print("swift-syntax present in package graph:", "swift-syntax" in json.dumps(d))
PY
swift build --target PostgREST 2>&1 | grep -ci "swift-syntax" || echo "0 swift-syntax lines when building PostgREST alone"
```

Expected: swift-syntax appears in the *package* graph (it must, the plugin needs it) but building
`--target PostgREST` compiles none of it. Record the output in the commit message. Task 11 turns this
into a permanent check.

- [ ] **Step 6: Format, spell-check, commit**

```bash
./scripts/format.sh
./scripts/spell-check.sh
git add Package.swift Package.resolved Sources/PostgrestMacros/ Sources/PostgrestMacrosPlugin/ \
        Tests/PostgrestMacrosTests/
git commit -m "feat(postgrest): add the PostgrestMacros targets

A compiler-plugin target plus a thin opt-in library. PostgREST and
Supabase do not depend on either, so swift-syntax is compiled only for
users who import PostgrestMacros. The plugin is exempt from
InternalImportsByDefault, which rejects the public conformances
SwiftSyntax's CompilerPlugin protocol requires."
```

---

## Task 8: The `@Table` macro and its markers

**Files:**
- Create: `Sources/PostgrestMacrosPlugin/TableMacro.swift`
- Create: `Sources/PostgrestMacrosPlugin/Support/CamelToSnake.swift`
- Create: `Sources/PostgrestMacrosPlugin/Support/StoredProperty.swift`
- Modify: `Sources/PostgrestMacros/Macros.swift`
- Modify: `Sources/PostgrestMacrosPlugin/Plugin.swift`
- Test: `Tests/PostgrestMacrosTests/TableMacroTests.swift`

**Interfaces:**
- Consumes: the protocols from Task 3.
- Produces: `@Table(_ name: String, schema: String = "public", readOnly: Bool = false)`, and the
  markers `@Column(_ name: String)`, `@PrimaryKey`, `@Default`. The expansion supplies
  `relationName`, `schema`, `selectString`, `CodingKeys`, `columnName(for:)`, and — unless
  `readOnly` — nested `Insert` and `Update` types.

- [ ] **Step 1: Write the failing expansion test**

`Tests/PostgrestMacrosTests/TableMacroTests.swift`:

```swift
import MacroTesting
import Testing

@testable import PostgrestMacrosPlugin

@Suite(.macros(["Table": TableMacro.self]))
struct TableMacroTests {
  @Test
  func expandsAWritableTable() {
    assertMacro {
      """
      @Table("todos")
      struct Todo {
        @PrimaryKey var id: Int
        var task: String
        @Default var isDone: Bool
        @Column("due_at") var dueDate: Date?
      }
      """
    } expansion: {
      """
      struct Todo {
        @PrimaryKey var id: Int
        var task: String
        @Default var isDone: Bool
        @Column("due_at") var dueDate: Date?

        enum CodingKeys: String, CodingKey {
          case id = "id"
          case task = "task"
          case isDone = "is_done"
          case dueDate = "due_at"
        }

        struct Insert: Encodable, Sendable {
          var task: String
          var isDone: Bool?
          var dueDate: Date?
        }

        struct Update: Encodable, Sendable {
          var task: String?
          var isDone: Bool?
          var dueDate: Date?
        }
      }

      extension Todo: PostgrestWritableRelation {
        static let relationName = "todos"
        static let schema = "public"
        static let selectString = "*"
        static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String {
          switch keyPath {
          case \\Self.id:
            return "id"
          case \\Self.task:
            return "task"
          case \\Self.isDone:
            return "is_done"
          case \\Self.dueDate:
            return "due_at"
          default:
            return ""
          }
        }
      }
      """
    }
  }

  @Test
  func readOnlyTableOmitsInsertAndUpdate() {
    assertMacro {
      """
      @Table("active_todos", readOnly: true)
      struct ActiveTodo {
        var id: Int
      }
      """
    } expansion: {
      """
      struct ActiveTodo {
        var id: Int

        enum CodingKeys: String, CodingKey {
          case id = "id"
        }
      }

      extension ActiveTodo: PostgrestRelation {
        static let relationName = "active_todos"
        static let schema = "public"
        static let selectString = "*"
        static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String {
          switch keyPath {
          case \\Self.id:
            return "id"
          default:
            return ""
          }
        }
      }
      """
    }
  }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter TableMacroTests`
Expected: FAIL to compile — `cannot find 'TableMacro' in scope`.

- [ ] **Step 3: Write the name conversion**

`Sources/PostgrestMacrosPlugin/Support/CamelToSnake.swift`:

```swift
/// Converts a Swift property name to its snake_case database column name.
///
/// `isDone` becomes `is_done`; `dueDate` becomes `due_date`; an already-lowercase name is unchanged.
/// Runs of capitals are treated as one word, so `htmlURL` becomes `html_url`.
func camelToSnakeCase(_ name: String) -> String {
  var out = ""
  var previousWasUpper = false
  for (index, character) in name.enumerated() {
    if character.isUppercase {
      let nextIsLower = name.dropFirst(index + 1).first?.isLowercase ?? false
      if index > 0, !previousWasUpper || nextIsLower {
        out.append("_")
      }
      out.append(Character(character.lowercased()))
      previousWasUpper = true
    } else {
      out.append(character)
      previousWasUpper = false
    }
  }
  return out
}
```

- [ ] **Step 4: Write the stored-property reader**

`Sources/PostgrestMacrosPlugin/Support/StoredProperty.swift`:

```swift
import SwiftSyntax

/// One stored property of an annotated type, with the marker attributes that affect it.
struct StoredProperty {
  var name: String
  var type: String
  var isOptional: Bool
  var isPrimaryKey: Bool
  var hasDefault: Bool
  var explicitColumn: String?

  /// The database column name: an explicit `@Column`, otherwise the snake_case form.
  var columnName: String { explicitColumn ?? camelToSnakeCase(name) }
}

extension StructDeclSyntax {
  /// Reads the stored properties, ignoring computed properties and static members.
  func postgrestStoredProperties() -> [StoredProperty] {
    memberBlock.members.compactMap { member -> StoredProperty? in
      guard
        let variable = member.decl.as(VariableDeclSyntax.self),
        !variable.modifiers.contains(where: { $0.name.text == "static" }),
        let binding = variable.bindings.first,
        let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
        let annotation = binding.typeAnnotation?.type,
        binding.accessorBlock == nil
      else { return nil }

      let attributes = variable.attributes.compactMap {
        $0.as(AttributeSyntax.self)
      }
      func attribute(_ name: String) -> AttributeSyntax? {
        attributes.first { $0.attributeName.trimmedDescription == name }
      }

      let column = attribute("Column")?
        .arguments?.as(LabeledExprListSyntax.self)?.first?
        .expression.as(StringLiteralExprSyntax.self)?
        .representedLiteralValue

      let typeText = annotation.trimmedDescription
      return StoredProperty(
        name: identifier.identifier.text,
        type: typeText,
        isOptional: typeText.hasSuffix("?") || typeText.hasPrefix("Optional<"),
        isPrimaryKey: attribute("PrimaryKey") != nil,
        hasDefault: attribute("Default") != nil,
        explicitColumn: column
      )
    }
  }
}
```

- [ ] **Step 5: Write the macro**

`Sources/PostgrestMacrosPlugin/TableMacro.swift`:

```swift
import SwiftSyntax
import SwiftSyntaxMacros

public struct TableMacro: MemberMacro, ExtensionMacro {
  // MARK: Arguments

  private struct Arguments {
    var name: String
    var schema: String
    var readOnly: Bool
  }

  private static func arguments(from node: AttributeSyntax) -> Arguments {
    var name = ""
    var schema = "public"
    var readOnly = false
    for argument in node.arguments?.as(LabeledExprListSyntax.self) ?? [] {
      switch argument.label?.text {
      case nil:
        name =
          argument.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue ?? ""
      case "schema":
        schema =
          argument.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue ?? "public"
      case "readOnly":
        readOnly = argument.expression.as(BooleanLiteralExprSyntax.self)?.literal.text == "true"
      default:
        break
      }
    }
    return Arguments(name: name, schema: schema, readOnly: readOnly)
  }

  // MARK: Members

  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard let structDeclaration = declaration.as(StructDeclSyntax.self) else {
      throw MacroExpansionErrorMessage("@Table can only be applied to a struct")
    }
    let arguments = arguments(from: node)
    let properties = structDeclaration.postgrestStoredProperties()

    let codingKeys = DeclSyntax(
      """
      enum CodingKeys: String, CodingKey {
      \(raw: properties.map { "  case \($0.name) = \"\($0.columnName)\"" }.joined(separator: "\n"))
      }
      """
    )

    guard !arguments.readOnly else { return [codingKeys] }

    let insertFields = properties
      .filter { !$0.isPrimaryKey }
      .map { property -> String in
        let optional = property.isOptional || property.hasDefault
        let type = optional && !property.isOptional ? "\(property.type)?" : property.type
        return "  var \(property.name): \(type)"
      }
      .joined(separator: "\n")

    let updateFields = properties
      .filter { !$0.isPrimaryKey }
      .map { property -> String in
        let type = property.isOptional ? property.type : "\(property.type)?"
        return "  var \(property.name): \(type)"
      }
      .joined(separator: "\n")

    return [
      codingKeys,
      DeclSyntax("struct Insert: Encodable, Sendable {\n\(raw: insertFields)\n}"),
      DeclSyntax("struct Update: Encodable, Sendable {\n\(raw: updateFields)\n}"),
    ]
  }

  // MARK: Conformance

  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    guard let structDeclaration = declaration.as(StructDeclSyntax.self) else { return [] }
    let arguments = arguments(from: node)
    let properties = structDeclaration.postgrestStoredProperties()
    let conformance = arguments.readOnly ? "PostgrestRelation" : "PostgrestWritableRelation"

    let cases = properties
      .map { "    case \\Self.\($0.name):\n      return \"\($0.columnName)\"" }
      .joined(separator: "\n")

    return [
      try ExtensionDeclSyntax(
        """
        extension \(type.trimmed): \(raw: conformance) {
          static let relationName = "\(raw: arguments.name)"
          static let schema = "\(raw: arguments.schema)"
          static let selectString = "*"
          static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String {
            switch keyPath {
        \(raw: cases)
            default:
              return ""
            }
          }
        }
        """
      )
    ]
  }
}
```

- [ ] **Step 6: Declare the macros and register them**

Append to `Sources/PostgrestMacros/Macros.swift`:

```swift
/// Synthesizes ``PostgrestRelation`` conformance for a struct that maps to a relation.
///
/// Property names convert camelCase to snake_case; `@Column` overrides a single name. The generated
/// `CodingKeys` and the generated column mapping come from the same input, so an insert body and a
/// filter can never disagree about a column.
///
/// - Parameters:
///   - name: The relation's name as PostgREST addresses it.
///   - schema: The Postgres schema. Defaults to `"public"`.
///   - readOnly: Pass `true` for a view. The type then conforms to ``PostgrestRelation`` only, and
///     the write methods are not available on it.
@attached(member, names: named(CodingKeys), named(Insert), named(Update))
@attached(extension, conformances: PostgrestRelation, PostgrestWritableRelation)
public macro Table(
  _ name: String,
  schema: String = "public",
  readOnly: Bool = false
) = #externalMacro(module: "PostgrestMacrosPlugin", type: "TableMacro")

/// Overrides the database column name for a property.
@attached(peer)
public macro Column(_ name: String) = #externalMacro(
  module: "PostgrestMacrosPlugin", type: "MarkerMacro"
)

/// Marks a property as the relation's primary key, excluding it from the generated `Insert`.
@attached(peer)
public macro PrimaryKey() = #externalMacro(
  module: "PostgrestMacrosPlugin", type: "MarkerMacro"
)

/// Marks a property as having a database default, making it optional in the generated `Insert`.
@attached(peer)
public macro Default() = #externalMacro(
  module: "PostgrestMacrosPlugin", type: "MarkerMacro"
)
```

Create `Sources/PostgrestMacrosPlugin/MarkerMacros.swift`:

```swift
import SwiftSyntax
import SwiftSyntaxMacros

/// The marker attributes carry no expansion of their own — `@Table` reads them off the properties.
public struct MarkerMacro: PeerMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    []
  }
}
```

Update `Sources/PostgrestMacrosPlugin/Plugin.swift`:

```swift
let providingMacros: [any Macro.Type] = [TableMacro.self, MarkerMacro.self]
```

- [ ] **Step 7: Run the expansion tests**

Run: `swift test --filter TableMacroTests`
Expected: PASS, 2 tests. `assertMacro` prints the actual expansion on mismatch — if the formatting
differs only in whitespace, copy the printed expansion into the `expansion:` block rather than
fighting the formatter.

- [ ] **Step 8: Add an end-to-end test**

`Tests/PostgrestMacrosTests/TableIntegrationTests.swift`:

```swift
import Foundation
import PostgrestMacros
import Testing

// Declared at file scope on purpose. `@Table` attaches an extension, and Swift does not allow an
// extension of a type nested inside another type, so annotating a nested struct fails to compile.
@Table("todos")
struct IntegrationTodo {
  @PrimaryKey var id: Int
  var task: String
  @Default var isDone: Bool
}

@Suite
struct TableIntegrationTests {
  typealias Todo = IntegrationTodo

  @Test
  func macroSuppliesTheRelationName() {
    #expect(Todo.relationName == "todos")
    #expect(Todo.schema == "public")
  }

  @Test
  func macroMapsKeyPathsToSnakeCase() {
    #expect(Todo.columnName(for: \.isDone) == "is_done")
  }

  @Test
  func insertExcludesThePrimaryKey() throws {
    let data = try JSONEncoder().encode(Todo.Insert(task: "buy milk", isDone: nil))
    let json = String(decoding: data, as: UTF8.self)
    #expect(json.contains("\"id\"") == false)
  }
}
```

Run: `swift test --filter TableIntegrationTests`
Expected: PASS, 3 tests.

- [ ] **Step 9: Format, spell-check, commit**

```bash
./scripts/format.sh
./scripts/spell-check.sh
git add Sources/PostgrestMacros/ Sources/PostgrestMacrosPlugin/ Tests/PostgrestMacrosTests/
git commit -m "feat(postgrest): add the @Table macro and its marker attributes

CodingKeys and the column mapping are generated from one input, so the
write path and the filter path cannot disagree about a column name.
@PrimaryKey is excluded from Insert and @Default is optional there;
readOnly: true conforms to PostgrestRelation only."
```

---

## Task 9: `@SelectionOf` for column subsets

Spec §4.5 tier 1, columns only. `@Relationship` and embeds are out of scope for slice 0.

**Files:**
- Create: `Sources/PostgrestMacrosPlugin/SelectionOfMacro.swift`
- Modify: `Sources/PostgrestMacros/Macros.swift`
- Modify: `Sources/PostgrestMacrosPlugin/Plugin.swift`
- Modify: `Sources/PostgREST/Query/PostgrestTypedSource.swift`
- Test: `Tests/PostgrestMacrosTests/SelectionOfMacroTests.swift`

**Interfaces:**
- Consumes: `PostgrestSelection`, `PostgrestTypedSource`.
- Produces: `@SelectionOf(_ relation: Any.Type)`, and
  `PostgrestTypedSource.select<S: PostgrestSelection>(_ selection: S.Type) -> PostgrestTypedQuery<R, [S]>`.

- [ ] **Step 1: Write the failing expansion test**

`Tests/PostgrestMacrosTests/SelectionOfMacroTests.swift`:

```swift
import MacroTesting
import Testing

@testable import PostgrestMacrosPlugin

@Suite(.macros(["SelectionOf": SelectionOfMacro.self]))
struct SelectionOfMacroTests {
  @Test
  func expandsAColumnSubset() {
    assertMacro {
      """
      @SelectionOf(Todo.self)
      struct TodoSummary {
        var id: Int
        @Column("due_at") var dueDate: Date?
      }
      """
    } expansion: {
      """
      struct TodoSummary {
        var id: Int
        @Column("due_at") var dueDate: Date?

        enum CodingKeys: String, CodingKey {
          case id = "id"
          case dueDate = "due_at"
        }
      }

      extension TodoSummary: PostgrestSelection {
        static let selectString = "id,due_at"
        /// Fails to compile if a property does not name a column on Todo.
        private static let _columnCheck: [String] = [
          Todo.columnName(for: \\Todo.id),
          Todo.columnName(for: \\Todo.dueDate),
        ]
      }
      """
    }
  }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter SelectionOfMacroTests`
Expected: FAIL to compile — `cannot find 'SelectionOfMacro' in scope`.

- [ ] **Step 3: Write the macro**

`Sources/PostgrestMacrosPlugin/SelectionOfMacro.swift`:

```swift
import SwiftSyntax
import SwiftSyntaxMacros

public struct SelectionOfMacro: MemberMacro, ExtensionMacro {
  private static func relationName(from node: AttributeSyntax) throws -> String {
    guard
      let expression = node.arguments?.as(LabeledExprListSyntax.self)?.first?.expression,
      let base = expression.as(MemberAccessExprSyntax.self)?.base
    else {
      throw MacroExpansionErrorMessage("@SelectionOf requires a relation type, e.g. @SelectionOf(Todo.self)")
    }
    return base.trimmedDescription
  }

  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard let structDeclaration = declaration.as(StructDeclSyntax.self) else {
      throw MacroExpansionErrorMessage("@SelectionOf can only be applied to a struct")
    }
    let properties = structDeclaration.postgrestStoredProperties()
    return [
      DeclSyntax(
        """
        enum CodingKeys: String, CodingKey {
        \(raw: properties.map { "  case \($0.name) = \"\($0.columnName)\"" }.joined(separator: "\n"))
        }
        """
      )
    ]
  }

  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    guard let structDeclaration = declaration.as(StructDeclSyntax.self) else { return [] }
    let relation = try relationName(from: node)
    let properties = structDeclaration.postgrestStoredProperties()
    let selectString = properties.map(\.columnName).joined(separator: ",")
    let checks = properties
      .map { "    \(relation).columnName(for: \\\(relation).\($0.name))," }
      .joined(separator: "\n")

    return [
      try ExtensionDeclSyntax(
        """
        extension \(type.trimmed): PostgrestSelection {
          static let selectString = "\(raw: selectString)"
          /// Fails to compile if a property does not name a column on \(raw: relation).
          private static let _columnCheck: [String] = [
        \(raw: checks)
          ]
        }
        """
      )
    ]
  }
}
```

The `_columnCheck` array is the cross-type check. A macro sees only syntax and cannot inspect
`Todo`'s members, but the *emitted* references are checked by the compiler, so a property that names
no column on the relation fails on that line.

- [ ] **Step 4: Declare the macro and register it**

Append to `Sources/PostgrestMacros/Macros.swift`:

```swift
/// Declares a named subset of a relation's columns.
///
/// Property names follow the same snake_case conversion as ``Table(_:schema:readOnly:)``, and
/// `@Column` overrides one. The expansion emits references to the relation's columns, so a property
/// that names no column on it fails to compile.
///
/// - Parameter relation: The relation this selects from, for example `Todo.self`.
@attached(member, names: named(CodingKeys))
@attached(extension, conformances: PostgrestSelection)
public macro SelectionOf(_ relation: Any.Type) = #externalMacro(
  module: "PostgrestMacrosPlugin", type: "SelectionOfMacro"
)
```

Add `SelectionOfMacro.self` to `providingMacros` in `Plugin.swift`.

- [ ] **Step 5: Add the `select(_:)` overload**

In `Sources/PostgREST/Query/PostgrestTypedSource.swift`, add to `PostgrestTypedSource`:

```swift
/// Selects the columns declared by a selection type.
///
/// - Parameter selection: A type declaring the columns to fetch, normally annotated with
///   `@SelectionOf`.
/// - Returns: A ``PostgrestTypedQuery`` decoding into `[S]`.
public func select<S: PostgrestSelection>(_ selection: S.Type) -> PostgrestTypedQuery<R, [S]> {
  PostgrestTypedQuery(builder: builder.select(S.selectString))
}
```

- [ ] **Step 6: Add an end-to-end test**

`Tests/PostgrestMacrosTests/SelectionIntegrationTests.swift`:

```swift
import Foundation
import PostgrestMacros
import Testing

// File scope, for the same reason as `TableIntegrationTests`: `@Table` and `@SelectionOf` both
// attach extensions, which cannot be nested inside another type.
@Table("todos")
struct SelectionTodo {
  @PrimaryKey var id: Int
  var task: String
  @Default var isDone: Bool
}

@SelectionOf(SelectionTodo.self)
struct SelectionTodoSummary {
  var id: Int
  var isDone: Bool
}

@Suite
struct SelectionIntegrationTests {
  typealias TodoSummary = SelectionTodoSummary

  @Test
  func selectStringListsTheDeclaredColumns() {
    #expect(TodoSummary.selectString == "id,is_done")
  }
}
```

Run: `swift test --filter SelectionIntegrationTests`
Expected: PASS.

- [ ] **Step 7: Format, spell-check, commit**

```bash
./scripts/format.sh
./scripts/spell-check.sh
git add Sources/PostgrestMacros/ Sources/PostgrestMacrosPlugin/ Sources/PostgREST/Query/ \
        Tests/PostgrestMacrosTests/
git commit -m "feat(postgrest): add @SelectionOf for column subsets

The expansion emits references to the relation's columns, so a property
that names no column on it is a compile error. Embeds via @Relationship
are deliberately out of scope for this slice."
```

---

## Task 10: Macro diagnostics

A macro whose failure mode is an unreadable expansion error is worse than no macro. Spec §4.5 names
three misuses that must be errors with actionable messages.

**Files:**
- Create: `Sources/PostgrestMacrosPlugin/Support/Diagnostics.swift`
- Modify: `Sources/PostgrestMacrosPlugin/TableMacro.swift`
- Modify: `Sources/PostgrestMacrosPlugin/SelectionOfMacro.swift`
- Test: `Tests/PostgrestMacrosTests/DiagnosticsTests.swift`

**Interfaces:**
- Consumes: `TableMacro`, `SelectionOfMacro` from Tasks 8 and 9.
- Produces: no new public API. Three diagnostics.

- [ ] **Step 1: Write the failing tests**

`Tests/PostgrestMacrosTests/DiagnosticsTests.swift`:

```swift
import MacroTesting
import Testing

@testable import PostgrestMacrosPlugin

@Suite(.macros(["Table": TableMacro.self, "SelectionOf": SelectionOfMacro.self]))
struct DiagnosticsTests {
  @Test
  func tableRejectsAClass() {
    assertMacro {
      """
      @Table("todos")
      class Todo {
        var id: Int = 0
      }
      """
    } diagnostics: {
      """
      @Table("todos")
      ┬──────────────
      ╰─ 🛑 @Table can only be applied to a struct
      class Todo {
        var id: Int = 0
      }
      """
    }
  }

  @Test
  func tableRejectsARelationshipProperty() {
    assertMacro {
      """
      @Table("todos")
      struct Todo {
        var id: Int
        @Relationship(\\Comment.todoID) var comments: [Comment]
      }
      """
    } diagnostics: {
      """
      @Table("todos")
      struct Todo {
        var id: Int
        @Relationship(\\Comment.todoID) var comments: [Comment]
        ┬──────────────────────────────
        ╰─ 🛑 @Relationship belongs on a @SelectionOf type, not on @Table
      }
      """
    }
  }

  @Test
  func selectionOfRequiresARelationType() {
    assertMacro {
      """
      @SelectionOf
      struct TodoSummary {
        var id: Int
      }
      """
    } diagnostics: {
      """
      @SelectionOf
      ┬───────────
      ╰─ 🛑 @SelectionOf requires a relation type, e.g. @SelectionOf(Todo.self)
      struct TodoSummary {
        var id: Int
      }
      """
    }
  }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter DiagnosticsTests`
Expected: `tableRejectsAClass` and `selectionOfRequiresARelationType` may already produce a thrown
error rather than a diagnostic attached to the right node — `assertMacro` prints what it actually got.
`tableRejectsARelationshipProperty` FAILS outright, since nothing checks for it yet.

- [ ] **Step 3: Write the diagnostic helper**

`Sources/PostgrestMacrosPlugin/Support/Diagnostics.swift`:

```swift
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// A diagnostic attached to a specific syntax node, so the error points at the offending code
/// rather than at the whole declaration.
struct PostgrestDiagnostic: DiagnosticMessage {
  let message: String
  var severity: DiagnosticSeverity { .error }
  var diagnosticID: MessageID { MessageID(domain: "PostgrestMacros", id: message) }
}

extension MacroExpansionContext {
  /// Emits an error pointing at `node`.
  func error(_ message: String, at node: some SyntaxProtocol) {
    diagnose(Diagnostic(node: node, message: PostgrestDiagnostic(message: message)))
  }
}
```

Add `.product(name: "SwiftDiagnostics", package: "swift-syntax")` to the
`PostgrestMacrosPlugin` target's dependencies in `Package.swift`.

- [ ] **Step 4: Emit the `@Relationship` diagnostic from `TableMacro`**

In both `expansion` methods of `TableMacro`, immediately after obtaining `structDeclaration`, add:

```swift
for member in structDeclaration.memberBlock.members {
  guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
  for attribute in variable.attributes.compactMap({ $0.as(AttributeSyntax.self) })
  where attribute.attributeName.trimmedDescription == "Relationship" {
    context.error(
      "@Relationship belongs on a @SelectionOf type, not on @Table",
      at: attribute
    )
    return []
  }
}
```

- [ ] **Step 5: Convert the thrown errors to attached diagnostics**

In `TableMacro`, replace `throw MacroExpansionErrorMessage("@Table can only be applied to a struct")`
with:

```swift
context.error("@Table can only be applied to a struct", at: node)
return []
```

Do the same in `SelectionOfMacro` for both its struct check and its missing-argument check, changing
`relationName(from:)` from `throws -> String` to `-> String?` returning `nil` on failure, and having
each caller emit the diagnostic and return `[]`.

- [ ] **Step 6: Run the tests**

Run: `swift test --filter DiagnosticsTests`
Expected: PASS, 3 tests. If the caret positions in the expected output differ, copy `assertMacro`'s
printed actual output into the `diagnostics:` block — the caret rendering is `MacroTesting`'s, not
something to hand-compute.

- [ ] **Step 7: Format, spell-check, commit**

```bash
./scripts/format.sh
./scripts/spell-check.sh
git add Package.swift Sources/PostgrestMacrosPlugin/ Tests/PostgrestMacrosTests/DiagnosticsTests.swift
git commit -m "feat(postgrest): add actionable macro diagnostics

@Table on a class, @Relationship on a @Table property, and @SelectionOf
without a relation type now produce errors pointing at the offending node
instead of a confusing expansion failure."
```

---

## Task 11: Lock the dependency boundary and mark the API alpha

**Files:**
- Create: `Tests/PostgRESTTests/DependencyBoundaryTests.swift`
- Create: `scripts/check-postgrest-dependencies.sh`
- Modify: `Sources/PostgREST/Relations/PostgrestRelation.swift`
- Modify: `Sources/PostgREST/Query/PostgrestTypedSource.swift`
- Modify: `Sources/PostgREST/Query/PostgrestTypedQuery.swift`
- Modify: `Sources/PostgREST/Query/PostgrestTypedMutation.swift`
- Modify: `Sources/PostgREST/Query/PostgrestTypedQuery+Filters.swift`

**Interfaces:**
- Consumes: everything above.
- Produces: a script CI can run, and an alpha marker on every new public symbol.

- [ ] **Step 1: Write the boundary check**

`scripts/check-postgrest-dependencies.sh`:

```bash
#!/usr/bin/env bash
# Fails if the PostgREST target's compile closure pulls in swift-syntax.
#
# The typed query API is usable without the macros, and the macros live in a separate opt-in
# module. If PostgREST ever gains a swift-syntax dependency, every consumer starts paying
# swift-syntax build time whether they use the macros or not.
set -euo pipefail

output=$(swift build --target PostgREST 2>&1)

if grep -qiE "swift-?syntax" <<<"$output"; then
  echo "FAIL: building PostgREST compiled swift-syntax."
  grep -iE "swift-?syntax" <<<"$output" | head -5
  exit 1
fi

echo "OK: PostgREST builds without swift-syntax."
```

Make it executable:

```bash
chmod +x scripts/check-postgrest-dependencies.sh
```

- [ ] **Step 2: Run it to verify it passes**

Run: `./scripts/check-postgrest-dependencies.sh`
Expected: `OK: PostgREST builds without swift-syntax.`

Then verify the check actually catches a violation. Temporarily add
`.product(name: "SwiftSyntax", package: "swift-syntax")` to the `PostgREST` target's dependencies,
re-run, confirm it FAILS, then revert. A check that cannot fail is not a check.

- [ ] **Step 3: Add the compile-time usability test**

`Tests/PostgRESTTests/DependencyBoundaryTests.swift`:

```swift
import Testing

@testable import PostgREST

/// The typed API must be usable with a hand-written conformance, with no macro import.
///
/// `PostgRESTTests` does not depend on `PostgrestMacros`, so this file compiling at all is the
/// assertion.
@Suite
struct DependencyBoundaryTests {
  struct Todo: PostgrestWritableRelation {
    static let relationName = "todos"
    static let schema = "public"
    static let selectString = "*"

    var id: Int

    static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String {
      switch keyPath {
      case \Self.id: "id"
      default: fatalError("unmapped key path")
      }
    }

    struct Insert: Encodable, Sendable { var id: Int? }
    struct Update: Encodable, Sendable { var id: Int? }
  }

  @Test
  func typedApiWorksWithoutTheMacroModule() async throws {
    let capture = QueryCapture(body: #"[{"id":1}]"#)
    let rows = try await capture.client.from(Todo.self).select().eq(\.id, 1).execute().value
    #expect(rows.first?.id == 1)
  }
}
```

Run: `swift test --filter DependencyBoundaryTests`
Expected: PASS.

- [ ] **Step 4: Mark every new public symbol alpha**

Add this line to the DocC comment of `PostgrestSelection`, `PostgrestRelation`,
`PostgrestWritableRelation`, `PostgrestTypedSource`, `PostgrestTypedQuery`,
`PostgrestTypedMutation`, `PostgrestKeyPathFilterable`, and `PostgrestClient.from(_ type:)`:

```swift
/// > Warning: Alpha. This API is expected to change without a major version bump while feedback is
/// > being collected. See `docs/design/postgrest-v3.md`.
```

Do **not** use `@available(*, deprecated)` or `@_spi` for this. `@_spi` forces callers to annotate
every import, and the point of shipping this slice is that people try it.

- [ ] **Step 5: Run the whole suite**

```bash
swift build
swift test 2>&1 | tail -20
./scripts/spell-check.sh
./scripts/check-postgrest-dependencies.sh
```

Expected: build succeeds, all tests pass, spell-check exits 0, boundary check prints OK. Record the
test count in the PR description.

- [ ] **Step 6: Format, spell-check, commit**

```bash
./scripts/format.sh
./scripts/spell-check.sh
git add scripts/check-postgrest-dependencies.sh Tests/PostgRESTTests/DependencyBoundaryTests.swift \
        Sources/PostgREST/
git commit -m "feat(postgrest): lock the macro dependency boundary and mark the typed API alpha

A script CI can run asserts that building PostgREST compiles no
swift-syntax, and a test asserts the typed API is usable with a
hand-written conformance and no macro import."
```

- [ ] **Step 7: Wire the check into CI**

Add a step to `.github/workflows/ci.yml` in the job that already runs on macOS, after the build step:

```yaml
      - name: Check PostgREST dependency boundary
        run: ./scripts/check-postgrest-dependencies.sh
```

Commit:

```bash
git add .github/workflows/ci.yml
git commit -m "ci: check that PostgREST builds without swift-syntax"
```

---

## Out of scope for this plan

Every item below is in the spec and deliberately excluded from slice 0. Do not implement them here;
each is a later stage.

| Excluded | Where it lands |
|---|---|
| `@Relationship`, embeds, `embedded` / `requiring` | Stage 3 (spec §4.4, §4.5) |
| The filter expression tree, `or`, nesting, `!` | Stage 2 (spec §4.3) |
| Operator overloads (`==`, `&&`, `\|\|`) | Stage 3, after measuring type-check cost (spec §3) |
| Value-typed core, `PostgrestSource` as a struct over an immutable request | Stage 2 (spec §4.1) |
| `PostgrestRequestError`, typed throws | Stage 2 (spec §4.8, ADR 0001) |
| Reusing `HTTPRuntime` as the transport, and the public-visibility question | Stage 2 (spec §4.7, §7) |
| `execute()` returning the value directly, `count(.exact)` | Stage 2 (spec §4.8) |
| `@Function` and typed RPC | Stage 3 (spec §4.6) |
| Deprecating today's classes | Stage 4 |
| The `supabase gen types swift` generator | Stage 5 (spec §8.2) |
| Requiring a filter on `update` / `delete` | Open question (spec §7) |
| `gt`/`gte`/`lt`/`lte` with a nil value | Follow-up decision (Task 1) |

## Verification checklist for the whole slice

Run before opening the stage-1 PR:

```bash
./scripts/format.sh && git diff --exit-code   # formatting is already applied
swift build
swift test
./scripts/spell-check.sh
./scripts/check-postgrest-dependencies.sh
./scripts/build-for-library-evolution.sh
PLATFORM=IOS ./scripts/xcodebuild.sh
```

The library-evolution build matters here: it is what makes an enum case a binary break, and it is the
reason ADR 0001 exists. It must pass before any new public type ships.
