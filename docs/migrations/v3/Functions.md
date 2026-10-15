# Functions v3 migration

This file covers the changes to `FunctionsClient` and the Edge Functions API from v2 to v3. See
[the v3 migration overview](../../../V3_MIGRATION.md) for steps that apply to every module,
including `supabase.functions` and `SupabaseClientOptions.FunctionsOptions`.

## Silent changes

Changes that still compile but behave differently. Check each one by hand.

- **Default decoder.** Responses decode with the SDK decoder, which reads ISO 8601 dates, not
  `JSONDecoder()`. If a function returns dates as seconds since 1970, pass `decoder: JSONDecoder()`
  to `invoke` or set it in `Configuration.decoder`.
- **Default body encoder.** `.json(_:)` encodes with the SDK encoder, which writes `Date` as
  ISO 8601, not `JSONEncoder()`. Pass `.json(value, encoder: JSONEncoder())` to keep the old
  format.
- **Encoding failures throw.** A body that fails to encode now throws `FunctionsError` with kind
  `.invalidRequest` before the request goes out. In v2 the request went out with no body.
- **Network and decoding errors are wrapped.** `URLError` and `DecodingError` arrive as
  `FunctionsError` with kind `.transport` or `.decoding`; the original is in `underlyingError`.
  Search for `as URLError` and `as DecodingError` near `invoke` calls.
- **Cancellation.** A cancelled `invoke` throws `CancellationError`, not `URLError(.cancelled)`.
  Iterating a stream body from a cancelled task also throws `CancellationError`, where it used to
  end as if complete.
- **Headers are case-insensitive.** A per-call `content-type` now replaces `Content-Type`
  instead of sending both.
- **`Authorization` in options wins.** An `Authorization` header in `FunctionInvokeOptions.headers`
  now reaches the server. See the overview for the shared `Authorization` rule.

## Renames and type changes

| v2 | v3 |
| --- | --- |
| `final class FunctionsClient` | `struct FunctionsClient` (no `weak`, `===`, or `AnyObject`) |
| `FunctionsClient.decoder` | `FunctionsClient.configuration.decoder` |
| `FunctionsClient.requestIdleTimeout: TimeInterval` | `FunctionsClient.requestIdleTimeout: Duration` |
| `FunctionInvokeOptions(timeoutInterval: 30)` | `FunctionInvokeOptions(timeout: .seconds(30))` |
| `FunctionInvokeOptions(headers: ["X-Key": "v"])` | `FunctionInvokeOptions(headers: [HTTPField.Name("X-Key")!: "v"])` |
| `FunctionInvokeOptions(region: someString)` | `FunctionInvokeOptions(region: FunctionRegion(rawValue: someString))` |
| `FunctionInvokeOptions.Method` | `HTTPRequest.Method` (same `.get`, `.post`, `.put`, `.patch`, `.delete`) |
| `FunctionInvokeOptions(method: nil)` | omit `method:` (defaults to `.post`) |
| `FunctionInvokeOptions.Method(rawValue: s)` | `HTTPRequest.Method(s)` |
| `invoke(_:options:) -> Void` | `invoke(_:body:options:) -> FunctionResponse` (`@discardableResult`) |

## `FunctionsClient` takes a `Configuration`

The flat initializers and `setAuth(token:)` are gone. Pass a `FunctionsClient.Configuration`.
Give the token through `accessToken`, which runs before each request. Do not put
`Authorization` in `headers`. `fetch:` is replaced by `http:`; see the overview for transports.
`logger:` takes a swift-log `Logger`.

```swift
// v2
let functions = FunctionsClient(url: url, headers: ["apikey": apiKey], region: .usEast1)
functions.setAuth(token: session.accessToken)

// v3
let functions = FunctionsClient(
  configuration: .init(
    url: url,
    headers: [HTTPField.Name("apikey")!: apiKey],
    region: .usEast1,
    accessToken: { await tokenStore.currentAccessToken }
  )
)
```

`init(configuration:)` traps if `url` has no host.

## The body is an `invoke` argument

`FunctionInvokeOptions` no longer has a `body`. Pass a `FunctionBody` to `invoke` or `stream`.
Each factory sets the `Content-Type`.

| v2 | v3 |
| --- | --- |
| `options: .init(body: value)` | `body: .json(value)` |
| `options: .init(body: "hello")` | `body: .text("hello")` |
| `options: .init(body: data)` | `body: .data(data)` |
| `options: .init(headers: ["Content-Type": "image/jpeg"], body: jpeg)` | `body: .data(jpeg, contentType: "image/jpeg")` |
| `options: .init(body: value, encoder: e)` | `body: .json(value, encoder: e)` |

```swift
// v2
let order: Order = try await supabase.functions.invoke(
  "get-order",
  options: FunctionInvokeOptions(method: .post, body: ["id": 42])
)

// v3
let order: Order = try await supabase.functions.invoke(
  "get-order",
  body: .json(["id": 42]),
  options: FunctionInvokeOptions(method: .post)
)
```

## `invoke` returns `FunctionResponse`; the `decode:` closure is removed

`invoke(_:options:decode:)` is removed. Read the status, headers, and body from the returned
`FunctionResponse`. `invoke<T>` keeps working and gains an optional `as:` label.

```swift
// v2
let (status, data) = try await supabase.functions.invoke("render") { data, response in
  (response.statusCode, data)
}

// v3
let response = try await supabase.functions.invoke("render")
let (status, data) = (response.status.code, response.body)
let report = try response.decode(as: Report.self)
```

## `_invokeWithStreamedResponse` is replaced by `stream`

`stream(_:body:options:)` returns a `FunctionStreamResponse` with the status and headers. Its
`body` yields `ArraySlice<UInt8>` chunks, not `Data`. A non-2xx status now throws from `stream`
itself, not from the first iteration.

```swift
// v2
for try await chunk in supabase.functions._invokeWithStreamedResponse("chat", options: options) {
  parser.feed(chunk)
}

// v3
let response = try await supabase.functions.stream("chat", body: .json(prompt))
for try await chunk in response.body {
  parser.feed(Data(chunk))
}
```

## `FunctionsError` is a struct

The enum cases are gone. Match on `kind` instead. The status and body are in `response`.
`Kind` is an open set, so keep a fallback branch.

| v2 | v3 |
| --- | --- |
| `FunctionsError.relayError` | `error.kind == .relay` |
| `FunctionsError.httpError(code:data:)` | `error.kind == .server`, `error.response?.statusCode`, `error.response?.body` |

```swift
// v2
do {
  try await supabase.functions.invoke("hello")
} catch let FunctionsError.httpError(code, data) {
  print(code, String(decoding: data, as: UTF8.self))
}

// v3
do {
  try await supabase.functions.invoke("hello")
} catch let error as FunctionsError where error.kind == .server {
  if let response = error.response {
    print(response.statusCode, String(decoding: response.body, as: UTF8.self))
  }
}
```
