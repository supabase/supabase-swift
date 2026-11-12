# Querying Data

Select, insert, update and delete rows, and call database functions.

## Overview

Start each query with ``PostgrestClient/from(_:)``. The examples use `supabase.from(_:)`, which
calls the same method.

### Select rows

``PostgrestRequestBuilder/select(_:head:count:)`` reads rows. The column list uses the PostgREST
syntax, so it can rename columns and embed related tables.

```swift
let todos: [Todo] = try await supabase.from("todos")
  .select("id, task, is_done")
  .execute()
  .value
```

``PostgrestResponse/value`` is the decoded body. The type comes from the context, so annotate
the variable or the return type. The client decodes with
``PostgrestClient/Configuration/decoder``. Pass `decoder:` to
``PostgrestRequestBuilder/execute(options:decoder:)`` to use another one for a single call.

### Filter, order and limit

Filters come after the operation. Each one takes a column name and a value.

```swift
let urgent: [Todo] = try await supabase.from("todos")
  .select()
  .eq("is_done", value: false)
  .gte("priority", value: 3)
  .order("priority", ascending: false)
  .limit(10)
  .execute()
  .value
```

``PostgrestRequestBuilder/single()`` expects exactly one row and decodes it as one value, not
an array. ``PostgrestRequestBuilder/maybeSingle()`` expects one row or none.

```swift
let todo: Todo = try await supabase.from("todos")
  .select()
  .eq("id", value: 1)
  .single()
  .execute()
  .value
```

### Insert, update and delete

A write returns no rows unless you ask for them. Add `select()` to the chain to get the changed
rows back.

```swift
struct NewTodo: Encodable {
  var task: String
}

let created: Todo = try await supabase.from("todos")
  .insert(NewTodo(task: "Write the docs"))
  .select()
  .single()
  .execute()
  .value

try await supabase.from("todos")
  .update(["is_done": true])
  .eq("id", value: created.id)
  .execute()

try await supabase.from("todos")
  .delete()
  .eq("id", value: created.id)
  .execute()
```

An `update` or a `delete` without a filter changes every row that the row level security
policies let the user change. Always add a filter.

### Count rows

Pass `count:` to get the number of matching rows. With `head: true`, the server sends the count
and no rows.

```swift
let response = try await supabase.from("todos")
  .select(head: true, count: .exact)
  .execute()
print(response.count ?? 0)
```

### Call a function

``PostgrestClient/rpc(_:params:head:get:count:)`` calls a database function. Its result takes
the same filters and transforms as a `select`.

```swift
struct Params: Encodable {
  var minPriority: Int

  enum CodingKeys: String, CodingKey {
    case minPriority = "min_priority"
  }
}

let todos: [Todo] = try await supabase.rpc("urgent_todos", params: Params(minPriority: 3))
  .execute()
  .value
```

### Another schema

``PostgrestClient/schema(_:)`` returns a client for another exposed schema.

```swift
let rows: [AuditEntry] = try await supabase.schema("audit").from("entries")
  .select()
  .execute()
  .value
```

### Retries and timeouts

The client retries `GET` and `HEAD` requests that fail with a transient error, up to three
attempts. It never replays a write. ``PostgrestRequestBuilder/retry(enabled:)`` changes this for
one request, and ``PostgrestRequestBuilder/timeout(_:)`` sets the timeout for one request.
