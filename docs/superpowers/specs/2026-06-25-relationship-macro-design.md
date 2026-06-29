# @Relationship Macro Design

## Overview

Adds `@Relationship` support to `@SelectionOf` structs so PostgREST join queries can be expressed with type-safe Swift KeyPaths. Relationships are intentionally NOT part of `@Table` — the table type represents a plain row, and projections with joins are declared separately via `@SelectionOf`.

---

## Decisions

| Question | Decision |
|---|---|
| Where is `@Relationship` declared? | Always explicit on the `@SelectionOf` field — never inferred |
| Does `@Table.selectString` include relationships? | No — stays `"*"` |
| What if a `@SelectionOf` field is non-primitive without `@Relationship`? | Compile-time diagnostic error (Approach B — strict) |
| What if a `@Table` field has `@Relationship`? | Compile-time diagnostic error |
| How is the FK column identified? | Via a `KeyPath` — no string literals |
| How is the referenced type identified? | Inferred from the field's type annotation (unwraps `Optional` and `Array`) |

---

## Architecture

### Role separation

```
@Table("messages")          ← row type only; no relationships allowed
struct Message {
  var id: UUID
  var senderId: UUID        ← FK column lives here as a plain field
  var body: String
}

@SelectionOf(Message.self)  ← projection / join query
struct MessageWithSender {
  var id: UUID
  var body: String
  @Relationship(\Message.senderId) var sender: User    ← FK on Message
}
```

`@Table` types know nothing about joins. Join shape is declared in `@SelectionOf` structs, which can be composed independently of the base table type.

### Module boundaries (unchanged)

- `SupabaseMacros` — macro plugin containing `SelectionOfMacro`, `TableMacro`, `RelationshipMacro`
- `SupabaseSwiftMacros` — library target re-exporting macro declarations + protocols + typed builders

---

## `@Relationship` Declaration

```swift
@attached(peer)
public macro Relationship<Root: ReadOnlyTableRepresentable>(_ keyPath: AnyKeyPath) =
  #externalMacro(module: "SupabaseMacros", type: "RelationshipMacro")
```

`RelationshipMacro` itself is a no-op peer macro — it exists so the attribute is valid Swift syntax. All real work is done in `SelectionOfMacro` when it reads the `@Relationship` attribute off each field.

The `references:` parameter from the original design is **removed**. The referenced type is read from the field's type annotation, unwrapping `Optional` and `Array` wrappers:
- `User` → `User`
- `User?` → `User`
- `[User]` → `User`
- `[User]?` → `User`

---

## KeyPath Argument

The KeyPath root identifies which table owns the FK column:

```swift
// FK on the @SelectionOf source table (Message has sender_id)
@Relationship(\Message.senderId) var sender: User?

// FK on the referenced table (Message has user_id → for a User@SelectionOf)
@Relationship(\Message.userId) var messages: [Message]
```

**Short form `\.senderId`:** `SelectionOfMacro` knows the parent table from `@SelectionOf(Message.self)` and generates `Message.columnName(for: \.senderId)` in the expanded code. Whether the attribute itself accepts the short form without an explicit root depends on how Swift resolves the macro argument — to be confirmed during implementation. If it doesn't work, the explicit form `\Message.senderId` is required.

**Type safety:** The generated code calls `Root.columnName(for: keyPath)` where `Root` is taken from the key path's root type. If `Root` doesn't conform to `ReadOnlyTableRepresentable` (no `@Table`), or the property doesn't exist, the generated code fails to compile with a clear Swift error.

---

## `SelectionOfMacro` Changes

Field classification loop:

```
for each stored property in @SelectionOf struct:
  if type is a known primitive:
    → parts.append("columnName")
  else if @Relationship present:
    → extract keyPath expression
    → determine root type name (explicit root or parent table from @SelectionOf arg)
    → determine base referenced type name (from field type annotation)
    → parts.append("fieldName:\(Ref.tableName)!\(Root.columnName(for: keyPath))(\(Ref.selectString))")
  else:
    → emit error: "Embedded type 'X' in '@SelectionOf' requires '@Relationship'."
    → stop expansion
```

Known primitives (unchanged set): `UUID`, `String`, `Int`, `Int8`, `Int16`, `Int32`, `Int64`, `UInt`, `UInt8`, `UInt16`, `UInt32`, `UInt64`, `Bool`, `Double`, `Float`, `Decimal`, `Date`, `Data`, `URL`, `AnyJSON`.

`CodingKeys` generation is unchanged — all fields (primitives and relationship fields) are included, since the full PostgREST response contains both scalar columns and embedded objects.

### Generated output example

```swift
@SelectionOf(Message.self)
struct MessageWithSender {
  var id: UUID
  var body: String
  @Relationship(\Message.senderId) var sender: User
  @Relationship(\Message.receiverId) var receiver: User
}

// Expands to:
extension MessageWithSender: SelectionRepresentable {
  public static var selectString: String {
    var parts: [String] = []
    parts.append("id")
    parts.append("body")
    parts.append("sender:\(User.tableName)!\(Message.columnName(for: \Message.senderId))(\(User.selectString))")
    parts.append("receiver:\(User.tableName)!\(Message.columnName(for: \Message.receiverId))(\(User.selectString))")
    return parts.joined(separator: ",")
  }
}

extension MessageWithSender {
  public enum CodingKeys: String, CodingKey {
    case id
    case body
    case sender
    case receiver
  }
}
```

At runtime, `User.tableName = "users"`, `User.selectString = "*"` (or whatever the User `@Table` synthesizes), and `Message.columnName(for: \Message.senderId) = "sender_id"`, producing:

```
id,body,sender:users!sender_id(*),receiver:users!receiver_id(*)
```

---

## `TableMacro` Changes

When `TableMacro` encounters any field annotated with `@Relationship`, it emits a diagnostic error and stops expansion:

```swift
@Table("messages")
struct Message {
  var id: UUID
  @Relationship(\User.id) var sender: User
  // error: '@Relationship' fields are not allowed in '@Table'.
  //        Declare a '@SelectionOf' struct to join related tables.
}
```

The existing code that silently excluded `@Relationship` fields from `Insert`/`Update` while keeping them in `CodingKeys` is removed entirely and replaced with this error.

---

## Diagnostics

| Situation | Error message |
|---|---|
| `@Relationship` on a `@Table` field | `'@Relationship' fields are not allowed in '@Table'. Declare a '@SelectionOf' struct to join related tables.` |
| Non-primitive field in `@SelectionOf` without `@Relationship` | `Embedded type 'X' in '@SelectionOf' requires '@Relationship'. Add '@Relationship(\Table.fkColumn)' to this field.` |
| Referenced type has no `tableName`/`selectString` | Compile error from generated code — `'X' has no member 'tableName'` (not a macro diagnostic) |
| Key path property doesn't exist on root type | Compile error from generated code — `'X' has no member 'y'` |

---

## Testing

### `SupabaseMacrosTests/SelectionOfMacroTests.swift`

- `testRelationshipDisambiguationString` — `@Relationship(\Message.senderId) var sender: User` generates correct select part
- `testRelationshipArray` — `[User]` type annotation correctly unwrapped
- `testRelationshipOptional` — `User?` type annotation correctly unwrapped
- `testMultipleRelationships` — two `@Relationship` fields on same struct; both appear in select string
- `testNonPrimitiveWithoutRelationship` — emits diagnostic, no expansion
- `testRelationshipOnTableDiagnostic` (moved to `TableMacroTests`) — `@Relationship` on `@Table` field emits diagnostic

### `Tests/PostgRESTTests/TypedBuildersTests.swift`

- HTTP-level snapshot test: `select(MessageWithSender.self)` sends the correct PostgREST query string with full disambiguation syntax
