# Generated Database Types for supabase-swift

**Date:** 2026-06-24  
**Status:** Draft  
**Scope:** PostgREST module + new SupabaseMacros target  
**Breaking change:** No — additive wrapper layer over existing string-based API

---

## Overview

Add compile-time type-safe database queries to supabase-swift by combining:

1. **CLI codegen** — `supabase gen types swift` emits `@Table`-annotated structs from the live schema
2. **Swift Macros** — `@Table`, `@SelectionOf<T>` etc. synthesize protocols, Insert/Update types, column name resolution, and select strings at compile time
3. **Typed wrapper layer** — `TypedPostgrestQueryBuilder<Table>` and friends wrap the existing string-based builders, translating KeyPaths to column strings internally

The existing `client.from("todos")` string API is untouched. Migration is opt-in, table by table.

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  supabase CLI codegen                               │
│  supabase gen types swift → Database.swift          │
│  (emits @Table-annotated structs)                   │
└───────────────────┬─────────────────────────────────┘
                    │ generates
                    ▼
┌─────────────────────────────────────────────────────┐
│  Swift Macros  (new target: SupabaseMacros)         │
│  @Table  @Column  @PrimaryKey  @Default             │
│  @Relationship  @SelectionOf<T>                     │
└───────┬──────────────────────────┬──────────────────┘
        │ synthesizes              │ synthesizes
        ▼                          ▼
┌───────────────────┐   ┌──────────────────────────────┐
│  Protocol layer   │   │  Insert / Update nested types │
│  TableRepresentable│  │  (macro-generated per table)  │
│  SelectionRepres. │   └──────────────────────────────┘
└───────┬───────────┘
        │ consumed by
        ▼
┌─────────────────────────────────────────────────────┐
│  Typed wrapper layer  (new, in PostgREST module)    │
│  TypedPostgrestQueryBuilder<Table>                  │
│  TypedPostgrestFilterBuilder<Table, Selection>      │
│  TypedPostgrestTransformBuilder<Table, Selection>   │
└───────┬─────────────────────────────────────────────┘
        │ wraps (delegates to)
        ▼
┌─────────────────────────────────────────────────────┐
│  Existing string-based builders  (unchanged)        │
│  PostgrestQueryBuilder / FilterBuilder / etc.       │
└─────────────────────────────────────────────────────┘
```

---

## Package Structure

Two new SPM targets. Swift macros require a separate executable target.

```swift
// Package.swift additions
.macro(
  name: "SupabaseMacros",
  dependencies: [
    .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
    .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
  ]
),
.target(
  name: "SupabaseSwiftMacros",
  dependencies: [.target(name: "SupabaseMacros")]
),
// PostgREST target gains:
// .target(name: "SupabaseSwiftMacros")
```

The umbrella `Supabase` module re-exports `SupabaseSwiftMacros`, so users importing `Supabase` need no additional imports.

### Test dependency

```swift
.testTarget(
  name: "SupabaseMacrosTests",
  dependencies: [
    .target(name: "SupabaseMacros"),
    .product(name: "MacroTesting", package: "swift-macro-testing"),
  ]
)
// Add to dependencies:
// .package(url: "https://github.com/pointfreeco/swift-macro-testing", from: "0.5.0")
```

All macro expansion tests use [swift-macro-testing](https://github.com/pointfreeco/swift-macro-testing) — it asserts the exact expanded source output and produces clear diffs on failure.

---

## Protocol Layer

```swift
public protocol SelectionRepresentable: Decodable {
  static var selectString: String { get }
}

// For views / read-only tables — synthesized by @Table(readOnly: true)
// Shared base for both protocols so TypedPostgrestFilterBuilder can use a single constraint.
public protocol ReadOnlyTableRepresentable: SelectionRepresentable {
  static var tableName: String { get }
  static var schema: String { get }
  static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String
}

// For read-write tables — synthesized by @Table (without readOnly: true)
// Refines ReadOnlyTableRepresentable by adding Insert and Update associated types.
public protocol TableRepresentable: ReadOnlyTableRepresentable {
  associatedtype Insert: Encodable
  associatedtype Update: Encodable
}
```

`TableRepresentable` inherits `SelectionRepresentable` with `selectString = "*"`, so a full-table select requires no explicit selection type at the call site. Views conforming to `ReadOnlyTableRepresentable` make `.insert()`, `.update()`, and `.delete()` unavailable at compile time.

---

## The `@Table` Macro

### Input (CLI-generated or hand-written)

```swift
@Table("todos", schema: "public")
public struct Todo {
  @PrimaryKey public var id: UUID
  public var title: String
  @Default public var isComplete: Bool
  public var userId: UUID?

  @Relationship("user_id", references: Profile.self)
  public var profile: Profile?
}
```

### Marker macros

| Macro | Effect on Insert | Effect on Update |
|---|---|---|
| `@PrimaryKey` | field excluded | field excluded |
| `@Default` | field `Optional` with `= nil` | field `Optional` with `= nil` |
| `@Column("name")` | overrides snake_case derivation | same |
| `@Relationship(...)` | field excluded | field excluded |
| _(plain)_ | field required | field `Optional` with `= nil` |

`@Column`, `@PrimaryKey`, `@Default`, and `@Relationship` are lightweight marker macros with no runtime behaviour. `@Table` (an `@attached(member)` macro) reads their presence to drive synthesis.

### Synthesized output

```swift
// TableRepresentable + SelectionRepresentable conformances
extension Todo: TableRepresentable {
  public static let tableName = "todos"
  public static let schema = "public"
  public static let selectString = "*"
}

// Insert — PrimaryKey excluded, Default fields optional
extension Todo {
  public struct Insert: Encodable {
    public var title: String
    public var isComplete: Bool? = nil
    public var userId: UUID? = nil

    enum CodingKeys: String, CodingKey {
      case title
      case isComplete = "is_complete"
      case userId = "user_id"
    }
  }
}

// Update — all columns optional, relationships excluded
extension Todo {
  public struct Update: Encodable {
    public var title: String? = nil
    public var isComplete: Bool? = nil
    public var userId: UUID? = nil

    enum CodingKeys: String, CodingKey {
      case title
      case isComplete = "is_complete"
      case userId = "user_id"
    }
  }
}

// CodingKeys for Row decoding (includes relationship for embedded responses)
extension Todo {
  enum CodingKeys: String, CodingKey {
    case id, title
    case isComplete = "is_complete"
    case userId = "user_id"
    case profile
  }
}

// KeyPath → column name bridge
extension Todo {
  public static func columnName<V>(for keyPath: KeyPath<Todo, V>) -> String {
    switch keyPath {
    case \.id:         return "id"
    case \.title:      return "title"
    case \.isComplete: return "is_complete"
    case \.userId:     return "user_id"
    default:           preconditionFailure("Unknown column keypath on Todo — macro bug")
    }
  }
  // The default branch is unreachable in practice — macro generates one case per
  // stored non-relationship property. preconditionFailure signals a macro bug, not
  // a user error.
}
```

---

## The `@SelectionOf<T>` Macro

Applied to a struct representing a partial column projection of table `T`. Validated entirely at compile time.

### Rules

- Every field name must match a `@Column`/plain property on `T` (not a `@Relationship`) with the exact same Swift type, OR
- Every field name must match a `@Relationship` on `T`, with a type that is either the referenced table's type or a `@SelectionOf` of that table.
- Fields can be omitted freely — omission means the column is not selected.
- For nullable columns (`UUID?` on parent), the `@SelectionOf` field may be either `UUID?` (preserves nullability) or `UUID` (asserts non-null — decode failure at runtime if null arrives). The macro emits a warning but not an error for the narrowing case.

### Examples

**Partial projection:**
```swift
@SelectionOf<Todo>
struct TodoSummary {
  let id: UUID
  let title: String
}
// selectString = "id,title"
```

**Relationship — full row:**
```swift
@SelectionOf<Todo>
struct TodoWithProfile {
  let id: UUID
  let title: String
  let profile: Profile      // @Relationship on Todo references Profile.self → "profile(*)"
}
// selectString = "id,title,profile(*)"
```

**Relationship — nested selection:**
```swift
@SelectionOf<Profile>
struct ProfileName {
  let id: UUID
  let name: String
}

@SelectionOf<Todo>
struct TodoWithProfileName {
  let id: UUID
  let title: String
  let profile: ProfileName  // @SelectionOf<Profile> → "profile(id,name)"
}
// selectString = "id,title,profile(id,name)"
```

**Compile-time errors:**
```swift
@SelectionOf<Todo>
struct Bad {
  let nonexistent: String  // error: 'nonexistent' is not a column on Todo
  let title: Int           // error: type mismatch — Todo.title is String, not Int
  let profile: Post        // error: Todo has no @Relationship producing Post
}
```

### Synthesized output (for `TodoSummary`)

```swift
extension TodoSummary: SelectionRepresentable {
  public static let selectString = "id,title"
}

extension TodoSummary: Decodable {
  enum CodingKeys: String, CodingKey {
    case id, title
  }
}
```

---

## Typed Query Builder Layer

Three generic structs wrap the existing builders. Each holds the underlying string-based builder and translates typed inputs before delegating.

### `PostgrestClient` extension

```swift
extension PostgrestClient {
  public func from<T: TableRepresentable>(_ table: T.Type) -> TypedPostgrestQueryBuilder<T>
}
```

### `TypedPostgrestQueryBuilder<Table>`

```swift
public struct TypedPostgrestQueryBuilder<Table: TableRepresentable> {
  private let underlying: PostgrestQueryBuilder

  // SELECT
  public func select(
    head: Bool = false,
    count: CountOption? = nil
  ) -> TypedPostgrestFilterBuilder<Table, Table>

  public func select<S: SelectionRepresentable>(
    _ selection: S.Type,
    head: Bool = false,
    count: CountOption? = nil
  ) -> TypedPostgrestFilterBuilder<Table, S>

  // INSERT / UPSERT — no filter chaining needed, falls back to existing builder
  public func insert(
    _ value: Table.Insert,
    returning: PostgrestReturningOptions = .representation,
    count: CountOption? = nil
  ) -> PostgrestTransformBuilder

  public func insert(
    _ values: [Table.Insert],
    returning: PostgrestReturningOptions = .representation,
    count: CountOption? = nil
  ) -> PostgrestTransformBuilder

  public func upsert(
    _ value: Table.Insert,
    onConflict: String? = nil,
    returning: PostgrestReturningOptions = .representation,
    count: CountOption? = nil,
    ignoreDuplicates: Bool = false
  ) -> PostgrestTransformBuilder

  // UPDATE / DELETE — filter chaining stays typed
  public func update(
    _ value: Table.Update,
    returning: PostgrestReturningOptions = .representation,
    count: CountOption? = nil
  ) -> TypedPostgrestFilterBuilder<Table, Table>

  public func delete(
    returning: PostgrestReturningOptions = .representation,
    count: CountOption? = nil
  ) -> TypedPostgrestFilterBuilder<Table, Table>
}
```

### `TypedPostgrestFilterBuilder<Table, Selection>`

```swift
public struct TypedPostgrestFilterBuilder<
  Table: TableRepresentable,
  Selection: SelectionRepresentable
> {
  private let underlying: PostgrestFilterBuilder

  // Typed filters — KeyPath replaces column name string
  public func eq<V: PostgrestFilterValue>(_ column: KeyPath<Table, V>, value: V) -> Self
  public func neq<V: PostgrestFilterValue>(_ column: KeyPath<Table, V>, value: V) -> Self
  public func gt<V: PostgrestFilterValue>(_ column: KeyPath<Table, V>, value: V) -> Self
  public func gte<V: PostgrestFilterValue>(_ column: KeyPath<Table, V>, value: V) -> Self
  public func lt<V: PostgrestFilterValue>(_ column: KeyPath<Table, V>, value: V) -> Self
  public func lte<V: PostgrestFilterValue>(_ column: KeyPath<Table, V>, value: V) -> Self
  public func `in`<V: PostgrestFilterValue>(_ column: KeyPath<Table, V>, values: [V]) -> Self
  public func like<V>(_ column: KeyPath<Table, V>, pattern: String) -> Self
  public func ilike<V>(_ column: KeyPath<Table, V>, pattern: String) -> Self
  public func `is`<V>(_ column: KeyPath<Table, V?>, value: Bool?) -> Self

  // String escape hatch for complex expressions
  public func filter(_ column: String, operator op: String, value: String) -> Self
  public func or(_ filters: String, referencedTable: String? = nil) -> Self

  // Transforms
  public func order<V>(
    _ column: KeyPath<Table, V>,
    ascending: Bool = true,
    nullsFirst: Bool = false
  ) -> TypedPostgrestTransformBuilder<Table, Selection>

  public func limit(_ count: Int) -> TypedPostgrestTransformBuilder<Table, Selection>
  public func range(from: Int, to: Int) -> TypedPostgrestTransformBuilder<Table, Selection>
  public func single() -> TypedSingleResultBuilder<Table, Selection>

  // Execute
  public func execute() async throws -> PostgrestResponse<[Selection]>
}
```

### `TypedPostgrestTransformBuilder<Table, Selection>`

```swift
public struct TypedPostgrestTransformBuilder<
  Table: TableRepresentable,
  Selection: SelectionRepresentable
> {
  private let underlying: PostgrestTransformBuilder

  public func order<V>(
    _ column: KeyPath<Table, V>,
    ascending: Bool = true,
    nullsFirst: Bool = false
  ) -> Self

  public func limit(_ count: Int) -> Self
  public func range(from: Int, to: Int) -> Self
  public func single() -> TypedSingleResultBuilder<Table, Selection>

  public func execute() async throws -> PostgrestResponse<[Selection]>
}
```

### `TypedSingleResultBuilder<Table, Selection>`

```swift
public struct TypedSingleResultBuilder<
  Table: TableRepresentable,
  Selection: SelectionRepresentable
> {
  private let underlying: PostgrestTransformBuilder
  public func execute() async throws -> PostgrestResponse<Selection>
}
```

### End-to-end example

```swift
// Full table, multiple rows
let todos: [Todo] = try await client
  .from(Todo.self)
  .select()
  .eq(\.isComplete, value: false)
  .order(\.title)
  .limit(10)
  .execute()
  .value

// Partial projection
let summaries: [TodoSummary] = try await client
  .from(Todo.self)
  .select(TodoSummary.self)
  .eq(\.userId, value: currentUserId)
  .execute()
  .value

// Nested relationship
let items: [TodoWithProfileName] = try await client
  .from(Todo.self)
  .select(TodoWithProfileName.self)
  .execute()
  .value

// Insert
try await client
  .from(Todo.self)
  .insert(Todo.Insert(title: "Buy milk"))
  .execute()

// Update with filter
try await client
  .from(Todo.self)
  .update(Todo.Update(isComplete: true))
  .eq(\.id, value: todoId)
  .execute()

// Single result
let todo: Todo = try await client
  .from(Todo.self)
  .select()
  .eq(\.id, value: todoId)
  .single()
  .execute()
  .value
```

---

## CLI Codegen Output

`supabase gen types swift` emits a single `Database.swift` file organized by schema. The CLI uses existing schema introspection (same source as `--lang typescript`) and applies the following rules:

| Postgres concept | Swift output |
|---|---|
| Primary key with default | `@PrimaryKey var field: Type` |
| Column with default | `@Default var field: Type` |
| Nullable column | `var field: Type?` |
| Foreign key column | `@Relationship("fk_col", references: Other.self) var rel: Other?` |
| Custom enum | Generated `enum Name: String, Codable, PostgrestFilterValue` |
| View | `@Table(..., readOnly: true)` — conforms to `ReadOnlyTableRepresentable` (no Insert/Update); `.insert()`, `.update()`, `.delete()` are unavailable at compile time |
| auth/storage schemas | Emitted under `// MARK: - auth schema` sections |

### Postgres → Swift type mapping

| Postgres | Swift |
|---|---|
| `uuid` | `UUID` |
| `text`, `varchar`, `char` | `String` |
| `bool` | `Bool` |
| `int2`, `int4` | `Int` |
| `int8` | `Int` |
| `float4`, `float8` | `Double` |
| `numeric` | `Decimal` |
| `timestamptz`, `timestamp` | `Date` |
| `date` | `Date` |
| `json`, `jsonb` | `AnyJSON` |
| `_type` (array) | `[SwiftType]` |
| custom enum | generated `enum` |

### Example output

```swift
// Generated by Supabase CLI — do not edit manually.
// Run `supabase gen types swift` to regenerate.

import Foundation
import Supabase

// MARK: - Enums

public enum Priority: String, Codable, PostgrestFilterValue {
  case low, medium, high
}

// MARK: - public schema

@Table("todos", schema: "public")
public struct Todo {
  @PrimaryKey public var id: UUID
  public var title: String
  @Default public var isComplete: Bool
  public var userId: UUID?
  @Default public var createdAt: Date

  @Relationship("user_id", references: Profile.self)
  public var profile: Profile?
}

@Table("profiles", schema: "public")
public struct Profile {
  @PrimaryKey public var id: UUID
  public var name: String
  public var email: String
}

// MARK: - Views (read-only)

@Table("todo_stats", schema: "public", readOnly: true)
public struct TodoStats {
  public var userId: UUID
  public var totalCount: Int
  public var completedCount: Int
}
```

---

## Testing Strategy

### Macro tests — swift-macro-testing

All `@Table` and `@SelectionOf` expansion tests use [swift-macro-testing](https://github.com/pointfreeco/swift-macro-testing), which asserts the exact expanded source and diffs on failure.

```swift
import MacroTesting
import XCTest

final class TableMacroTests: XCTestCase {
  override func invokeTest() {
    withMacroTesting(macros: ["Table": TableMacro.self, "PrimaryKey": PrimaryKeyMacro.self]) {
      super.invokeTest()
    }
  }

  func testBasicTableExpansion() {
    assertMacro {
      """
      @Table("todos")
      struct Todo {
        @PrimaryKey var id: UUID
        var title: String
        @Default var isComplete: Bool
      }
      """
    } expansion: {
      """
      struct Todo {
        @PrimaryKey var id: UUID
        var title: String
        @Default var isComplete: Bool
      }

      extension Todo: TableRepresentable {
        static let tableName = "todos"
        static let schema = "public"
        static let selectString = "*"
      }

      extension Todo {
        struct Insert: Encodable {
          var title: String
          var isComplete: Bool? = nil
          enum CodingKeys: String, CodingKey {
            case title
            case isComplete = "is_complete"
          }
        }
      }
      // ... etc
      """
    }
  }

  func testSelectionOfValidation() {
    assertMacro {
      """
      @SelectionOf<Todo>
      struct Bad {
        let nonexistent: String
      }
      """
    } diagnostics: {
      """
      @SelectionOf<Todo>
      struct Bad {
        let nonexistent: String
            ┬──────────
            ╰─ 🛑 'nonexistent' is not a column on Todo
      }
      """
    }
  }
}
```

### Builder tests

Typed builder tests verify that the correct PostgREST URL parameters are constructed. Use the existing `Mocker`-based test infrastructure in `Tests/PostgRESTTests/`.

### Integration tests

Add typed-API variants to the existing integration test suite.

---

## Migration Path

The existing string-based API is untouched. Migration is opt-in and table by table.

**Step 1** — Add `swift-macro-testing` (dev only) and the new targets to `Package.swift`.

**Step 2** — Generate `Database.swift`:
```bash
supabase gen types swift --local > Sources/YourApp/Database.swift
```

**Step 3** — Delete manual `Decodable` model structs that are now covered by the generated types.

**Step 4** — Migrate query call sites from string API to typed API:
```swift
// Before
let todos: [Todo] = try await client
  .from("todos")
  .select()
  .eq("is_complete", value: false)
  .execute()
  .value

// After
let todos: [Todo] = try await client
  .from(Todo.self)
  .select()
  .eq(\.isComplete, value: false)
  .execute()
  .value
```

**Step 5** — Adopt `@SelectionOf` for partial projections wherever manual column strings were used.

The string-based `from("todos")` path remains available indefinitely as an escape hatch for dynamic table names or tables not present in the generated schema.

---

## Out of Scope (v1)

- RPC function typed wrappers
- Storage bucket types
- Auth schema table types
- Compile-time validated `.or()` / complex filter expressions
- Full column-projection return type narrowing without `@SelectionOf` (Swift's type system limitation)
