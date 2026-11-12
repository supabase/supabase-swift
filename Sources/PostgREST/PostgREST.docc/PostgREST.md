# ``PostgREST``

Read and write Postgres tables, views and functions through the PostgREST API.

## Overview

``PostgrestClient`` is the client for the `/rest/v1` API. With `SupabaseClient`, call
`supabase.from(_:)`, `supabase.rpc(_:params:)` and `supabase.schema(_:)`. You can also build a
client on its own with ``PostgrestClient/init(configuration:)`` (see <doc:Standalone>).

A query is a chain of builders. ``PostgrestClient/from(_:)`` names a table or a view. The next
call selects the operation. Filters and transforms follow. Nothing is sent until you call
``PostgrestRequestBuilder/execute(options:decoder:)``.

```swift
struct Todo: Codable {
  var id: Int
  var task: String
  var isDone: Bool
}

let todos: [Todo] = try await supabase.from("todos")
  .select()
  .eq("is_done", value: false)
  .order("id")
  .execute()
  .value
```

Each builder is an immutable value. A call returns a changed copy, so you can keep a base query
and build more than one request from it.

Every failure is a ``PostgrestError`` or a `CancellationError`. See <doc:HandlingErrors>.

## Topics

### Essentials

- <doc:QueryingData>
- <doc:TypedQueries>
- <doc:HandlingErrors>
- <doc:Standalone>

### Client

- ``PostgrestClient``
- ``PostgrestClient/Configuration``

### Builders

- ``PostgrestQueryBuilder``
- ``PostgrestFilterBuilder``
- ``PostgrestTransformBuilder``
- ``PostgrestRequestBuilder``

### Requests and Responses

- ``PostgrestResponse``
- ``FetchOptions``
- ``CountOption``
- ``PostgrestReturning``
- ``PostgrestFilterValue``

### Errors

- ``PostgrestError``
