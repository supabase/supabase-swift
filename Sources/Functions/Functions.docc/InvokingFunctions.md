# Invoking Functions

Send a body, pick a method, and read the answer as a typed value or as raw bytes.

## Overview

``FunctionsClient/invoke(_:body:options:)`` sends one request to
`/functions/v1/<name>` and buffers the answer. The default is a `POST` with no body. The generic
``FunctionsClient/invoke(_:body:options:as:decoder:)`` does the same and JSON-decodes the body.

### JSON in, JSON out

``FunctionBody/json(_:encoder:)`` encodes any `Encodable` value and sets
`Content-Type: application/json`. The return type decides how the body is read: a `Decodable`
binding decodes it, a ``FunctionResponse`` binding keeps the bytes.

```swift
struct Order: Encodable { var id: Int }
struct Receipt: Decodable { var total: Decimal; var paidAt: Date }

let receipt: Receipt = try await supabase.functions.invoke("checkout", body: .json(Order(id: 42)))
let same = try await supabase.functions.invoke("checkout", body: .json(Order(id: 42)), as: Receipt.self)
```

Dates decode from ISO 8601 strings, the format a TypeScript function writes with
`JSON.stringify`. Pass `decoder:` to one call, or set ``FunctionsClient/Configuration/decoder``
for every call, to change that.

A call whose answer you do not need still compiles: `invoke` is `@discardableResult`.

```swift
try await supabase.functions.invoke("audit-log", body: .json(event))
```

### GET with a query

``FunctionInvokeOptions/method`` is an `HTTPRequest.Method` and
``FunctionInvokeOptions/query`` is appended to the URL. A sub-path goes in the name.

```swift
let response = try await supabase.functions.invoke(
  "report/monthly",
  options: .init(method: .get, query: [URLQueryItem(name: "month", value: "2026-09")])
)
let pdf = response.body
```

### Text, bytes and files

Each ``FunctionBody`` factory fixes the `Content-Type`.

```swift
try await supabase.functions.invoke("echo", body: .text("hello"))
try await supabase.functions.invoke("thumbnail", body: .data(jpeg, contentType: "image/jpeg"))
try await supabase.functions.invoke(
  "transcribe",
  body: .stream(try HTTPBody(fileURL: audioURL), contentType: "audio/m4a"),
  options: .init(timeout: .seconds(300))
)
```

``FunctionBody/stream(_:contentType:)`` sends the file without loading it into memory. A
streamed body can be read once, so the SDK never retries or replays it.

### Content-Type precedence

Headers merge lowest to highest: `X-Client-Info`, then ``FunctionsClient/Configuration/headers``,
then the body's `Content-Type`, then ``FunctionInvokeOptions/headers``. A client-wide
`Content-Type` cannot relabel a JSON body; a per-call one still wins.

```swift
try await supabase.functions.invoke(
  "ingest",
  body: .data(payload),
  options: .init(headers: [.contentType: "application/x-ndjson"])
)
```

### Region and timeout per call

``FunctionInvokeOptions/region`` overrides ``FunctionsClient/Configuration/region`` and goes out
as both the `x-region` header and the `forceFunctionRegion` query item. The gateway falls back to
the default region for one it does not know.

``FunctionInvokeOptions/timeout`` is an idle timeout for this call. When `nil`, the client's
`HTTPClientConfiguration.timeout` applies, or ``FunctionsClient/requestIdleTimeout`` (150
seconds, the gateway's own limit) when that is `nil` too.

```swift
try await supabase.functions.invoke(
  "render",
  options: .init(region: .euWest1, timeout: .seconds(30))
)
```

### Reading the head

``FunctionResponse`` carries every header. ``FunctionResponse/region`` and
``FunctionResponse/executionID`` identify the worker that ran the call;
``FunctionResponse/requestID`` is what Supabase support asks for.

```swift
let response = try await supabase.functions.invoke("hello")
print(response.status, response.region ?? "unknown region", response.requestID ?? "-")
```
