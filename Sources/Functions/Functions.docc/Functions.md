# ``Functions``

Invoke Supabase Edge Functions: JSON in and out, raw bytes, streamed bodies and one error type.

## Overview

``FunctionsClient`` is the client for the `/functions/v1` gateway. Get one from
`supabase.functions`, or build one on its own with ``FunctionsClient/init(configuration:)``
(see <doc:Standalone>).

An invocation is one HTTP request. ``FunctionsClient/invoke(_:body:options:)`` buffers the
answer into a ``FunctionResponse``, ``FunctionsClient/invoke(_:body:options:as:decoder:)``
decodes it as JSON, and ``FunctionsClient/stream(_:body:options:)`` returns the head at once
and the body as it arrives.

```swift
struct Prompt: Encodable { var text: String }
struct Answer: Decodable { var text: String }

let answer: Answer = try await supabase.functions.invoke("ask", body: .json(Prompt(text: "hi")))
```

Every failure is a ``FunctionsError`` or a `CancellationError`. See <doc:Errors>.

## Topics

### Essentials

- <doc:InvokingFunctions>
- <doc:StreamingResponses>
- <doc:Errors>
- <doc:Standalone>

### Client

- ``FunctionsClient``
- ``FunctionsClient/Configuration``

### Requests

- ``FunctionBody``
- ``FunctionInvokeOptions``
- ``FunctionRegion``

### Responses

- ``FunctionResponse``
- ``FunctionStreamResponse``

### Errors

- ``FunctionsError``
