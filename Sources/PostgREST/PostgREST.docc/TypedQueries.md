# Typed Queries

Describe a table as a Swift type, and let the compiler check column names and value types.

## Overview

> Warning: The typed query API is experimental. Its shape can change in a minor release. A file
> that queries a typed table needs `@_spi(Experimental) import Supabase` or
> `@_spi(Experimental) import PostgREST`.

The untyped API takes column names as strings. A wrong name or a value of the wrong type fails at
run time. The typed API moves both checks to compile time.

### Declare a table

The `@Table` macro maps a struct to a table or a view. Declare the struct at file scope.

```swift
import Supabase

@Table("todos")
struct Todo {
  @PrimaryKey @Default var id: Int
  var task: String
  @Default var isDone: Bool
  @Column("due_at") var dueDate: Date?
}
```

- A property name converts from camelCase to snake_case: `isDone` is the column `is_done`.
- `@Column` sets a column name that the rule does not give.
- `@PrimaryKey` marks the primary key.
- `@Default` marks a column that has a default in the database, so an insert can leave it out.

Pass `readOnly: true` for a view. The write methods are then not available on the type.

### Generate the types

You do not have to write these structs by hand. The Supabase CLI writes them from your schema:

```bash
supabase gen types --lang swift --local > Sources/App/Database.swift
```

Run it again after each migration.

### Query a table

Pass the type to `from(_:)`. The result decodes as that type, with no annotation.

```swift
@_spi(Experimental) import Supabase

let todos = try await supabase.from(Todo.self).select().execute().value
```

Filter and order closures receive the columns of the table. Each column has its database name
and its Swift type, so an operand of the wrong type is a compile error.

```swift
let urgent = try await supabase.from(Todo.self)
  .select()
  .where { $0.isDone.eq(false) && $0.dueDate.lt(deadline) }
  .order { $0.dueDate.asc() }
  .execute()
  .value
```

The typed API always uses the SDK's default JSON coders. A key strategy in
``PostgrestClient/Configuration/encoder`` or ``PostgrestClient/Configuration/decoder`` applies
to the untyped builders only.

### Errors

Typed queries throw the same ``PostgrestError`` as untyped ones. See <doc:HandlingErrors>.
