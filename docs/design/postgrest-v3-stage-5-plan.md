# PostgREST v3 Stage 5 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `supabase gen types swift` emit relation and selection conformances the v3 typed
query API accepts, so a generated schema is a drop-in alternative to hand-written `@Table` types —
with no macro dependency.

**Architecture:** The generator emits **macro-free** conformances. It writes out `relationName`,
`schema`, `selectString`, `CodingKeys`, `columnName(for:)`, `Insert` and `Update` as plain Swift,
because generated code has no reason to pay swift-syntax build cost and because the protocols live in
`PostgREST`, not in `PostgrestMacros`. This is the same contract the macro satisfies, reached the
other way.

**Tech Stack:** Swift, in **this repository**. The generator is a Swift executable that reads
postgrest-typegen's `GeneratorMetadata` JSON document on standard input and writes the generated file
to standard output, the same pattern Dart's `supabase_typegen` follows in supabase-flutter.

**Linear:** SDK-2190, part of SDK-1641 (moving every bundled generator out of postgrest-typegen into
its own SDK repository). It replaces SDK-1584 to SDK-1587.

**Spec:** [`postgrest-v3.md`](./postgrest-v3.md) — §4.2 (the relation contract), §8.2 (what the
generator must agree with). **Read §8.2 first**; it carries the type mapping and two requirements
that are easy to miss.

**Depends on:** stage 1 for the protocol shapes, and ideally stage 4, so the generator targets the
API that is not about to be deprecated. It does **not** depend on stages 2 or 3 — the relation
contract is stable from stage 1 onward, and nothing generated uses `where`, embeds or `@Function`.

---

## Where it lives, and what that changes

This plan originally targeted postgres-meta's `src/server/templates/swift.ts`. That template moved to
`packages/postgrest-typegen/src/generation/swift.ts` in [supabase/sdk](https://github.com/supabase/sdk)
when postgres-meta started consuming `@supabase/postgrest-typegen` (postgres-meta#1084), and
postgrest-typegen no longer takes changes to its bundled generators: each one is moving into its own
SDK repository (SDK-1641). So the rewrite happens here, in Swift, next to the protocols it targets.

What that changes compared to the original plan:

- **Drift between the generator and `PostgREST` becomes catchable in this repository's CI.** The
  generator and the protocols change in the same pull request, and Task 5 compiles the generator's
  output against `PostgREST` on every run.
- **Introspection stays in postgrest-typegen.** The generator only consumes the `GeneratorMetadata`
  document, which carries a `version` field and is described by a published JSON Schema
  (`generatorMetadataJsonSchema`). Shape changes there are the remaining cross-repository risk.
- **The user-facing command is still `supabase gen types swift`**, in the Supabase CLI. The CLI
  resolves languages through the `@supabase/typegen` registry in supabase/sdk, so reaching this
  generator is a registry entry plus a CLI dependency bump, with no CLI code change (Task 7). It uses
  the same introspection as `--lang typescript`, as §8.2 requires.

## Global Constraints

- The generator emits **no macro attributes**. `@Table` and `@SelectionOf` are for hand-written code.
- Generated code must compile under the same settings the package uses: `ExistentialAny`,
  `InternalImportsByDefault`, `MemberImportVisibility`, Swift 6 language mode, and
  `-enable-library-evolution`.
- Generated types are `public` when the consuming app expects them to cross a module boundary. That
  means the generator must emit `public` on the protocol witnesses too — a witness must be at least
  as accessible as its conformance. SDK-1516 hit exactly this with the macro.
- Follow this repository's conventions (`AGENTS.md`) for the generator's own code.

---

## Task 1: Establish what the current template emits

**Files:** none changed. This is a read-and-record task.

- [ ] **Step 1: Capture the current output**

Run the existing Swift generator (`supabase gen types swift`, which today runs postgrest-typegen's
bundled `swift.ts`) against the `Tests/IntegrationTests/supabase` schema in this repo — it has tables,
a view and enums, so it exercises most of the mapping — and commit the output as a fixture here, next
to the `GeneratorMetadata` document it was generated from. Whatever else changes, the diff against
this baseline is the review.

- [ ] **Step 2: Record what it gets right**

The current generator already emits `Codable` structs with `CodingKeys`. That shape is reusable as a
reference; the new work is the protocol conformances, `Insert`/`Update`, and the enum conformance in
Task 3.

- [ ] **Step 3: Note every place the output would not compile against v3**

Most importantly: does it emit a single `Select` struct per relation? §7 records that it does, and
that whether the generator should also emit *selections* is undecided. Task 6 addresses it; do not
guess here.

---

## Task 2: Emit the relation conformance

**Files:**
- Create: a generator executable target in this package, reading `GeneratorMetadata` on standard input

**Interfaces:**
- Produces, per table or view:

```swift
public struct Todo: PostgrestWritableRelation, Decodable, Sendable, Hashable, Identifiable {
  public static let relationName = "todos"
  public static let schema = "public"
  public static let selectString = "*"

  public var id: UUID
  public var task: String
  public var isDone: Bool
  public var dueAt: Date?

  public enum CodingKeys: String, CodingKey {
    case id
    case task
    case isDone = "is_done"
    case dueAt = "due_at"
  }

  public static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String { /* switch */ }

  public struct Insert: Encodable, Sendable { /* … */ }
  public struct Update: Encodable, Sendable { /* … */ }
}
```

- [ ] **Step 0: Read and validate the metadata**

Decode the `GeneratorMetadata` JSON document from standard input and reject a `version` the
generator does not support with a clear message. Generate the `Decodable` model from
`generatorMetadataJsonSchema` or write it by hand; either way, test it against a document produced by
the current postgrest-typegen release.

- [ ] **Step 1: Map the write capability from the metadata**

§4.2's table is the whole rule, and it is deliberately coarse:

| Source | Conformance |
|---|---|
| Table | `PostgrestWritableRelation` |
| View with `is_updatable: true` | `PostgrestWritableRelation` |
| View with `is_updatable: false` | `PostgrestRelation` |
| Materialized view | `PostgrestRelation` |

When this was written, `PostgresView` exposed only a single `is_updatable` boolean and no trigger
flags, and `PostgresMaterializedView` exposed no write metadata at all. That is why the design has one
write capability rather than three — do not try to infer insert-only or delete-only views.

> **Changed since:** `GeneratorMetadata` views now also carry optional `is_insert_enabled` and
> `is_update_enabled`, which account for `INSTEAD OF` triggers and unconditional `INSTEAD` rules
> (`is_updatable` mirrors `information_schema.views` and ignores triggers). Materialized views still
> carry no write metadata, and there is still no delete flag. The single write capability does not
> have to change, but decide whether a view writable only through triggers should be a
> `PostgrestWritableRelation`, and whether an insert-only or update-only view still maps to
> `PostgrestRelation`.

- [ ] **Step 2: Derive `Insert` and `Update` from column metadata**

The generator has better information than the macro does: identity, default and nullability are all
in the metadata, so no attribute-reading is needed.

- `Insert` excludes identity columns; columns with a default or that are nullable become optional
- `Update` makes every non-identity column optional
- Both carry their own `CodingKeys`

That last point is not cosmetic. PostgREST's encoder sets **no** `keyEncodingStrategy` — verified in
`Sources/Helpers/Codable.swift` — so an `Insert` without `CodingKeys` sends `isDone` while a filter on
the same column sends `is_done`. SDK-1516 hit this with the macro; the generator must not repeat it.

- [ ] **Step 3: Emit explicit inits on `Insert` and `Update`, with `nil` defaults on optionals**

The memberwise init of a `public` struct is internal, so a generated `public` type would otherwise
expose an `Insert` that nothing outside the module can construct. And without `= nil` defaults a
one-column update reads `Todo.Update(task: nil, isDone: true, dueAt: nil)`. Same two defects SDK-1516
found in the macro path.

- [ ] **Step 4: `columnName(for:)` traps in its default arm**

Match what the macro emits: `fatalError` naming the type, not `return ""`. An empty column name
becomes an opaque PostgREST 400 that never names the key path.

- [ ] **Step 5: Update the fixture and review the diff against Task 1's baseline**

---

## Task 3: Postgres enums become `RawRepresentable` structs

**Files:**
- Modify: the generator target from Task 2

**Decided:** a Postgres enum generates a `RawRepresentable` **struct**, not a Swift `enum`.

- [ ] **Step 1: Emit the struct idiom**

```swift
public struct TodoStatus: RawRepresentable, Codable, Hashable, Sendable,
  ExpressibleByStringLiteral, PostgrestFilterValue
{
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  public static let pending: TodoStatus = "pending"
  public static let done: TodoStatus = "done"
}
```

This is the idiom `AGENTS.md` mandates under "Enum-like Values", and a generated Postgres enum is
squarely the case it is written for: a value that crosses the wire in both directions.

- [ ] **Step 2: `PostgrestFilterValue` needs no extra members — verified**

`PostgrestFilterValue` requires exactly `var rawValue: String { get }`, which the stored property
already witnesses. `postgrestArrayElement` comes from the protocol's own default extension
(`escapePostgRESTArrayLiteralElement(rawValue)`). So the conformance costs one line in the
inheritance clause and nothing else.

Without it a generated enum cannot be a filter operand at all (§8.2), which would make typed filters
unusable on exactly the columns where they matter most — status, role, kind.

- [ ] **Step 3: Full `Codable`, because the column travels both ways**

`AGENTS.md` says to conform to exactly the direction the type is used in. A column of enum type is
decoded from a select *and* encoded in `Insert`/`Update`, so this one genuinely needs both.

- [ ] **Step 4: Do not emit a `CaseIterable` substitute**

No `knownValues` array, no custom `Identifiable`. `AGENTS.md` is explicit: a consuming app keeps its
own list of the values it cares about — `Examples/Examples/Auth/KnownProviders.swift` is the pattern.
The static members are already the schema's list, and adding an array invites treating it as closed,
which is the thing this shape exists to prevent.

### Why a struct, concretely

The failure a Swift `enum` produces is not hypothetical. `enum TodoStatus: String, Codable` throws on
decode when it meets a value it has no case for. So the moment anyone adds a value to the Postgres
enum, **every already-shipped app decoding that column starts failing on those rows** — not
degrading, failing — until its owner regenerates and ships an update. A non-failable
`init(rawValue:)` round-trips the new value through `.rawValue` instead.

### Three consequences that must be written down

`AGENTS.md` requires a migration note for exactly this shape change, and names two of these:

- **`switch` stops being exhaustive.** Callers switching over a generated enum today must add a
  `default`. This is the real ergonomic cost and it is the whole trade.
- **`if let x = TodoStatus(rawValue: s)` goes from compiling to a compile error**, because the
  initializer is no longer failable.
- **`"\(status)"` silently stops printing the case name** and starts printing the struct
  description. Silent, so it needs saying loudest.

- [ ] **Step 5: Put the migration note where Swift users will see it**

The generated code lives in users' apps, so the primary note belongs in this repository's release
notes, with a pointer in the CLI changelog. Add an entry to `V3_MIGRATION.md` as well — a Swift
developer hitting a non-exhaustive `switch` after regenerating will look there first.

## Task 4: The type mapping

**Files:**
- Modify: the generator target from Task 2

§8.2's table is the contract:

| Postgres | Swift |
|---|---|
| `uuid` | `UUID` |
| `text`, `varchar`, `char` | `String` |
| `bool` | `Bool` |
| `int2`, `int4`, `int8` | `Int` |
| `float4`, `float8` | `Double` |
| `numeric` | `Decimal` |
| `timestamptz`, `timestamp`, `date` | `Date` |
| `json`, `jsonb` | `JSONValue` |
| `_type` (array) | `[SwiftType]` |
| custom enum | generated `RawRepresentable` struct (Task 3) |

- [ ] **Step 1: Implement the mapping and assert every row in a test**
- [ ] **Step 2: Decide what an unmapped type does**

Falling back to `JSONValue` keeps generation succeeding but produces a column a typed filter cannot
use. Failing loudly tells the user their schema needs attention. Pick one and document it; silent
fallback is the option that wastes the most time downstream.

- [ ] **Step 3: `Date` covers three Postgres types with different semantics**

`timestamptz`, `timestamp` and `date` all map to `Date`, which loses the distinction. PostgREST's
wire format and this SDK's decoder (`JSONDecoder.supabase()`, a custom `dateDecodingStrategy` in
`Sources/Helpers/Codable.swift`) determine whether all three actually round-trip. **Verify all three
against a live PostgREST** rather than assuming — this is the mapping row most likely to be wrong,
and §9 sets the precedent that server behavior gets checked rather than reasoned about.

---

## Task 5: A compile check against `PostgREST`

**Files:**
- Create: a fixture `GeneratorMetadata` document and its generated output, committed here
- Create: a test target that compiles the generated output against `PostgREST`

**This is the most valuable task in the stage.** Without it, nothing notices when a protocol change in
`PostgREST` breaks the generator. With the generator in this repository, the check runs on every pull
request that touches either side.

- [ ] **Step 1: Commit a representative `GeneratorMetadata` document**

Tables, an updatable view, a view writable only through triggers, a materialized view, enums, arrays,
nullable columns, a composite primary key. Produced by postgrest-typegen's introspection against a real
database, not hand-written to look like it.

- [ ] **Step 2: Regenerate and compile it as part of `swift test`**

Generate from the committed document in the test run, or check that the committed output matches the
generator, then build it. A target that only has to build is enough. The assertion is that it compiles
at all — the same shape as SDK-1515's dependency-boundary test, where the file compiling *is* the
assertion.

- [ ] **Step 3: Add a few behavioral assertions on top**

`relationName`, a snake-case `columnName(for:)`, an `Insert` that omits the identity column, and a
generated enum used as a filter operand. Those four cover the contract's load-bearing parts.

- [ ] **Step 4: Decide how the metadata fixture gets refreshed**

The committed document goes stale when the database schema or postgrest-typegen changes. Either a
documented manual step in `AGENTS.md`, or a CI job that regenerates and diffs. Manual is acceptable if
it is written down; undocumented is not.

- [ ] **Step 5: Record the version pairing**

Record the `GeneratorMetadata` `version` and the postgrest-typegen release the fixture came from next
to it, so a mismatch is diagnosable.

---

## Task 6: Record the two decisions this stage closes

Both questions this stage inherited are now answered. This task is about writing them down where the
next reader will find them, not about deciding them.

- [ ] **Step 1: Selections stay out of the generator**

**Decided: no generated selections.** Generated output stops at the relation contract.

Three reasons, worth keeping in the plan because this will be asked again:

- `@SelectionOf`'s cost — one declaration per shape — is the single open question the stage 1 alpha
  exists to gather feedback on (§7). Generating selection shapes before that feedback arrives
  answers it in advance with output nobody asked for.
- Naming generated selections has no obvious answer, which is why §7 recorded it as undecided rather
  than as work.
- A relation conformance is already enough to use the typed API end to end. A user who wants a column
  subset writes one `@SelectionOf` by hand, which is the same thing they would do for a hand-written
  relation.

Revisit after the alpha feedback lands. Do not treat this as permanent.

- [ ] **Step 2: Embeds fall out with selections, so there is nothing to reconcile yet**

Per §4.5, embeds are declared **by selections** — `@Relationship` sits on a `@SelectionOf` type and is
a compile error on a `@Table` one. With selections out, the generator emits no embeds, so the
`@Relationship` spelling divergence §8.2 records needs no reconciling in this stage.

That divergence is still resolved for whenever it does matter: the KeyPath form
`@Relationship(\Message.senderID)` won over the string form
`@Relationship("fk_col", references: Other.self)`, because the foreign key is itself a column, so the
KeyPath already exists and is compiler-checked. Stage 3 Task 2 is where that form lands.

- [ ] **Step 3: Update §7 of the spec**

Strike "Generated selection types" from the open-questions list and point it at this decision, the
same way §5 now points at the stage plans. An open question that has been answered but left open
gets re-litigated.

## Task 7: Reach the generator from `supabase gen types swift`

**Files (in supabase/sdk):**
- Modify: `packages/typegen/src/languages/` (the `swift` registry entry)
- Delete: `packages/postgrest-typegen/src/generation/swift.ts` and its tests

- [ ] **Step 1: Decide how the CLI runs the generator in the user's project**

The registry runs an external generator as a command in the user's project and pipes the metadata on
standard input, like `dart run supabase_typegen`. Pick the Swift equivalent (for example a SwiftPM
command plugin, or an executable product run with `swift run`) and the install hint shown when it is
missing.

- [ ] **Step 2: Switch the `swift` registry entry to the external command**

postgres-meta only serves in-process languages, so this drops its hosted `/generators/swift` route.
Check that nothing still calls it before switching.

- [ ] **Step 3: Release `@supabase/typegen` and bump it in the CLI and in postgres-meta**

- [ ] **Step 4: Delete the Swift generator from postgrest-typegen**

A breaking release of that package.

## Out of scope for this plan

- Introspection. It stays in postgrest-typegen; this plan only consumes its `GeneratorMetadata`.
- `@Function` descriptors for database functions — stage 3 defines the shape; whether the generator
  emits them is a follow-up.
- **Selections and embeds — decided out**, see Task 6. Revisit after the stage 1 alpha feedback.

## Verification checklist for the whole slice

- [ ] The generator's tests pass in `swift test`
- [ ] Generated output for the fixture schema compiles against `PostgREST` under Swift 6 language
      mode and `-enable-library-evolution`
- [ ] Every row of §8.2's type mapping has a test
- [ ] `timestamptz`, `timestamp` and `date` are each verified to round-trip against a live PostgREST
- [ ] A generated enum type is a `RawRepresentable` struct, works as a filter operand, and decodes a
      value absent from the schema it was generated from without throwing
- [ ] The `switch`-exhaustiveness, failable-init and interpolation consequences are documented in both
      this repository's release notes and `V3_MIGRATION.md`
- [ ] A generated `Insert` omits identity columns and sends snake_case keys
- [ ] Writing to a materialized view or a non-updatable view fails to compile
- [ ] The fixture's refresh procedure and `GeneratorMetadata` version pairing are documented
- [ ] `supabase gen types swift` runs this generator, and postgrest-typegen no longer ships one
