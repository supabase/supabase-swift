# Streaming Responses

Read a function's body as it arrives: server-sent events, large downloads, long-running jobs.

## Overview

``FunctionsClient/stream(_:body:options:)`` sends the request and returns a
``FunctionStreamResponse`` as soon as the response head arrives. The ``FunctionStreamResponse/body``
is an `HTTPBody`, an `AsyncSequence` of `ArraySlice<UInt8>` chunks. Iterate it once.

A relay failure or a non-2xx status throws ``FunctionsError`` from `stream` itself, before any
body exists, so the loop only ever sees a successful answer.

### Server-sent events

Chunk boundaries follow the network, not the payload. An event can arrive split across two
chunks, and two events can share one, so frame them yourself: buffer bytes and cut on the blank
line that ends an event.

```swift
let response = try await supabase.functions.stream("chat", body: .json(prompt))

var buffer = Data()
for try await chunk in response.body {
  buffer.append(contentsOf: chunk)
  while let range = buffer.range(of: Data("\n\n".utf8)) {
    let event = String(decoding: buffer[..<range.lowerBound], as: UTF8.self)
    buffer.removeSubrange(..<range.upperBound)
    let data = event.split(separator: "\n")
      .filter { $0.hasPrefix("data:") }
      .map { $0.dropFirst(5).trimmingCharacters(in: .whitespaces) }
      .joined(separator: "\n")
    if data == "[DONE]" { return }
    await render(data)
  }
}
```

`[DONE]` is an OpenAI convention, not part of the protocol; the SDK does not look for it. A
function that ends its stream closes the connection, and the loop ends on its own.

### Writing a byte stream to disk

For a large download, hand the body to `HTTPBody.write(to:)` instead of buffering it.

```swift
let export = try await supabase.functions.stream("export", options: .init(method: .get))
try await export.body.write(to: fileURL)
```

### Cancelling

Cancelling the task that iterates the body closes the connection and throws `CancellationError`
from the loop. To stop reading without an error, `break` instead.

```swift
let task = Task {
  let response = try await supabase.functions.stream("chat", body: .json(prompt))
  for try await chunk in response.body {
    await render(chunk)
  }
}
task.cancel()  // the loop throws CancellationError
```

In SwiftUI, `.task` cancels when the view disappears, so a chat screen needs no bookkeeping.

### Linux

On Linux `URLSessionTransport` buffers the whole response, so the body arrives as one chunk when
the server closes the connection. The code above still works; it just sees everything at once.
