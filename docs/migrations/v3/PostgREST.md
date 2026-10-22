# PostgREST v3 migration

This file covers the changes to `PostgrestClient` and the string query builders from v2.55.4 to
v3. See [the v3 migration overview](../../../V3_MIGRATION.md) for steps that apply to every
module.

## Silent changes

Changes that still compile but behave differently. Check each one by hand.

- **`update`, `upsert` and `delete` no longer return rows by default.** `returning` now defaults
  to `nil`, so no `Prefer: return=representation` is sent. Find each `update`, `upsert` or
  `delete` that reads `.value` and add `.select()` to the chain.
- **`order` no longer forces `NULLS LAST`.** `nullsFirst` is now `Bool?` and defaults to `nil`,
  so the database picks the null placement (`NULLS FIRST` on a descending sort). Pass
  `nullsFirst: false` to keep the v2 order.
- **`setHeader` and `retry` return a new builder.** The builders are structs, so a call whose
  result you drop has no effect. The compiler only gives an "unused result" warning. Chain the
  call, or assign its result.
- **Enum-like values accept any raw value.** `init(rawValue:)` on `PostgrestOperator`,
  `CountOption`, `PostgrestReturningOptions` and `TextSearchType` never returns `nil` now, so an
  `X(rawValue: s) != nil` check is always `true`. String interpolation prints
  `CountOption(rawValue: "exact")`, not `exact`. Use `.rawValue` where you need the string.
- **Error responses always decode.** A PostgREST error body is decoded with a fixed decoder, not
  your `Configuration.decoder`. Error bodies that failed to decode in v2 and came through as
  `HTTPError` are now a `PostgrestError`.
- **Retries wait with jitter.** PostgREST still retries `GET` and `HEAD` on a transient network
  failure, a 503 or a 520, up to three times. The wait is now random up to `min(30 s, 2^n s)`,
  and a `Retry-After` header is honored. Errors from a custom transport or middleware are no
  longer retried.
- **`csv()` with `stripNulls()` throws one message.** The request still fails before it is sent,
  as a `PostgrestError` of kind `.invalidRequest`. The message is now always
  "`` `.csv()` cannot be combined with `.stripNulls()` ``", whatever the call order. Search for
  code that matches the v2 message "`` `.stripNulls()` cannot be combined with `.csv()` ``".

## Renames and type changes

| v2 | v3 |
| --- | --- |
| `PostgrestClient.setAuth(_:)` | `accessToken:` closure on `PostgrestClient.init` and `Configuration.init` |
| `PostgrestClient(… fetch:)`, `Configuration(… fetch:)` | `http: HTTPClientConfiguration` (see the overview) |
| `PostgrestClient.FetchHandler` | `any ClientTransport` |
| `logger: (any SupabaseLogger)?` | `logger: Logging.Logger` |
| `PostgrestClient`, builders: `final class` | `struct` |
| `PostgrestBuilder` | `any PostgrestExecutableBuilder`, or `PostgrestFilterBuilder` / `PostgrestTransformBuilder` |
| `Configuration.encoder`, `.decoder`: `var` | `let`; pass them to `init`, or per call with `encoder:` / `decoder:` |
| `PostgrestFilterBuilder.Operator`: `enum` | `PostgrestOperator` struct (`Operator` is a type alias) |
| `CountOption`, `PostgrestReturningOptions`, `TextSearchType`: `enum` | `struct` with the same static members |
| `insert(…)`, `upsert(…)` return `PostgrestFilterBuilder` | return `PostgrestTransformBuilder` |
| `PostgrestResponse.response: HTTPURLResponse` | `PostgrestResponse.response: HTTPResponse` |
| `URLQueryRepresentable` | `PostgrestFilterValue` |
| `PostgrestFilterValue.queryValue` | `PostgrestFilterValue.rawValue` |
| `.like(_:value:)`, `.ilike(_:value:)` | `.like(_:pattern:)`, `.ilike(_:pattern:)` |
| `.in(_:value:)` | `.in(_:values:)` |
| `.plfts`, `.phfts`, `.wfts(_:query:config:)` | `.textSearch(_:query:config:type:)` with `.plain`, `.phrase`, `.websearch` |
| `.explain(…, format: String)` | `.explain(…, format: ExplainFormat)` |
| `PostgrestError.detail`, `init(detail:hint:code:message:)` | removed; see [Errors](#errors) |

A `switch` over `PostgrestOperator`, `CountOption`, `PostgrestReturningOptions` or
`TextSearchType` needs a `default:` case. `PostgrestOperator.allCases` is gone.

## Access token

```swift
// v2
let client = PostgrestClient(url: url)
client.setAuth(token)

// v3
let client = PostgrestClient(url: url, accessToken: { try await auth.session.accessToken })
```

An `Authorization` header in `headers:` or from `setHeader` wins over the closure.

## Value-type builders

Code that holds a builder or client as a reference type no longer compiles: `weak`, `unowned`,
`AnyObject`, `===` and subclasses. `setHeader` and `retry` are not available on the builder that
`from(_:)` returns; pick an operation first, or set the header on the client.

```swift
// v2
weak var database: PostgrestClient?
try await client.from("todos").setHeader(name: "Prefer", value: "params=single-object")
  .select(count: .exact).execute()

// v3
var database: PostgrestClient?
let client = PostgrestClient(url: url, headers: ["Prefer": "params=single-object"])
try await client.from("todos").select(count: .exact).execute()
```

When you call `execute` through `any PostgrestExecutableBuilder`, pass `decoder:`. A protocol
requirement has no default value.

```swift
// v2
let todos: [Todo] = try await builder.execute(options: FetchOptions()).value
// v3
let todos: [Todo] = try await builder.execute(options: FetchOptions(), decoder: nil).value
```

## No filters after `insert` or `upsert`

PostgREST ignores filters on a `POST`, so a filter after `insert` or `upsert` had no effect.
Delete it. All transforms (`select`, `order`, `single`, …) still compile.

```swift
// v2
try await client.from("todos").insert(todo).eq("id", value: 1).execute()
// v3
try await client.from("todos").insert(todo).execute()
```

## `nil` is not a filter value

`Optional` no longer conforms to `PostgrestFilterValue`, so `eq`, `neq`, `gt`, `like`, `in` and
the others do not take an optional. In v2, `eq(…, value: nil)` sent `eq.NULL` and could match the
wrong rows. Use `is` for `NULL`. Optional elements in an array (`contains("tags", value: ["a", nil])`)
still work.

```swift
// v2
try await client.from("users").select().eq("email", value: email).execute()  // email: String?

// v3
let query = client.from("users").select()
let scoped = email.map { query.eq("email", value: $0) } ?? query.is("email", value: nil)
try await scoped.execute()
```

## Errors

`PostgrestError` is a wrapper with `kind`, `message`, `serverError`, `response` and
`underlyingError`. The PostgREST body (`code`, `message`, `details`, `hint`) moves to
`serverError`. `HTTPError`, `URLError` and `DecodingError` from a query now arrive as a
`PostgrestError` with kind `.server`, `.transport` or `.decoding`. A throwing `accessToken`
closure gives kind `.accessToken`. `PostgrestError` is no longer `Codable`.

```swift
// v2
} catch let error as PostgrestError {
  if error.code == "23505" { showDuplicate(error.details) }
} catch let error as HTTPError {
  print(error.response.statusCode)
}

// v3
} catch let error as PostgrestError {
  if error.serverError?.code == "23505" { showDuplicate(error.serverError?.details) }
  print(error.response?.statusCode ?? 0, error.response?.requestID ?? "")
}
```

To create one yourself, pass a kind: `PostgrestError(kind: .invalidRequest, message: "…")`.

## Deprecated filter aliases

Fifteen second spellings on `PostgrestFilterBuilder` are deprecated. They still send the same
request. They are removed in v4.

| Deprecated | Use |
| --- | --- |
| `.equals(_:value:)` | `.eq(_:value:)` |
| `.notEquals(_:value:)` | `.neq(_:value:)` |
| `.greaterThan(_:value:)` | `.gt(_:value:)` |
| `.greaterThanOrEquals(_:value:)` | `.gte(_:value:)` |
| `.lowerThan(_:value:)` | `.lt(_:value:)` |
| `.lowerThanOrEquals(_:value:)` | `.lte(_:value:)` |
| `.rangeLowerThan(_:range:)` | `.rangeLt(_:range:)` |
| `.rangeGreaterThan(_:value:)` | `.rangeGt(_:range:)` |
| `.rangeGreaterThanOrEquals(_:value:)` | `.rangeGte(_:range:)` |
| `.rangeLowerThanOrEquals(_:value:)` | `.rangeLte(_:range:)` |
| `.fts(_:query:config:)` | `.textSearch(_:query:config:type:)` |
| `.fullTextSearch(_:query:config:)` | `.textSearch(_:query:config:type:)` |
| `.plainToFullTextSearch(_:query:config:)` | `.textSearch(_:query:config:type: .plain)` |
| `.phraseToFullTextSearch(_:query:config:)` | `.textSearch(_:query:config:type: .phrase)` |
| `.webFullTextSearch(_:query:config:)` | `.textSearch(_:query:config:type: .websearch)` |

```swift
// v2
.greaterThanOrEquals("age", value: "18").fullTextSearch("bio", query: "swift")
// v3
.gte("age", value: "18").textSearch("bio", query: "swift")
```

`match(_:)` with a dictionary is not deprecated.

## String builders

The v2 builders (`from("table")`, `rpc`, `PostgrestQueryBuilder`, `PostgrestFilterBuilder`,
`PostgrestTransformBuilder`) keep their names and stay supported in v3, apart from the changes
above. They moved to `Sources/PostgREST/Untyped/` and send requests through the same core as the
typed API. You do not need to move to the typed API.

## Experimental APIs

v3 adds a typed query API: the `@Table` and `@SelectionOf` macros, `from(Todo.self)` and
`schema(MySchema.self)`. The entry points are `@_spi(Experimental)`, and the types it declares
have a `_` prefix. The API can change in a minor release.

```swift
@_spi(Experimental) import Supabase

let todos = try await supabase.from(Todo.self).select().execute().value
```

`@_spi(Experimental) import PostgREST` works the same way. A file that only declares `@Table` or
`@SelectionOf` types does not need the SPI import.
