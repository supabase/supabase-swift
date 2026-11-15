# Testing with a Stub Transport

Test the code that calls Supabase without a network and without a server.

## Overview

Every request from every module goes through one `ClientTransport`. Replace it with your own
type, and your tests control each response.

### Write a stub transport

A `ClientTransport` has one method. It gets the request and returns the response head and the
body.

```swift
import Supabase

struct StubTransport: ClientTransport {
  var status: HTTPResponse.Status = .ok
  var json: String

  func send(_ request: HTTPRequest, body: HTTPBody?) async throws -> (HTTPResponse, HTTPBody?) {
    let head = HTTPResponse(status: status, headerFields: [.contentType: "application/json"])
    return (head, HTTPBody(Data(json.utf8)))
  }
}
```

### Give it to the client

Set the transport in the global HTTP configuration. Auth, the database, Storage and Edge
Functions then use it.

```swift
func makeClient(transport: any ClientTransport) throws -> SupabaseClient {
  try SupabaseClient(
    supabaseURL: URL(string: "https://test.supabase.co")!,
    supabaseKey: "test-key",
    configuration: .init(global: .init(http: .init(transport: transport)))
  )
}
```

Let the code under test receive the client as a parameter. Do not let it read a global client.

### Test a success

```swift
@Test func loadsTodos() async throws {
  let supabase = try makeClient(
    transport: StubTransport(json: #"[{"id": 1, "task": "Write tests"}]"#)
  )

  let todos: [Todo] = try await supabase.from("todos").select().execute().value

  #expect(todos.map(\.task) == ["Write tests"])
}
```

### Test a failure

Return an error status and an error body. The SDK then throws the module error, as it does
against a real server.

```swift
@Test func reportsADuplicate() async throws {
  let supabase = try makeClient(
    transport: StubTransport(
      status: .conflict,
      json: #"{"code": "23505", "message": "duplicate key value"}"#
    )
  )

  await #expect(throws: PostgrestError.self) {
    try await supabase.from("todos").insert(["task": "Write tests"]).execute()
  }
}
```

To test a network failure, throw a `URLError` from `send(_:body:)`. The SDK wraps it in the
module error with kind `transport`.

### Check the request

To check what your code sent, record the requests. An actor keeps the record safe.

```swift
actor RequestLog {
  private(set) var requests: [HTTPRequest] = []
  func add(_ request: HTTPRequest) { requests.append(request) }
}

struct RecordingTransport: ClientTransport {
  let log: RequestLog

  func send(_ request: HTTPRequest, body: HTTPBody?) async throws -> (HTTPResponse, HTTPBody?) {
    await log.add(request)
    return (HTTPResponse(status: .ok), HTTPBody(Data("[]".utf8)))
  }
}
```

### Things to know

- The SDK retries reads that fail with a transient error or status. Each retry calls your
  transport again. For a test of one failed read, turn retries off for that module, or count the
  calls.
- Realtime uses a WebSocket, not this transport. To test it, set
  `SupabaseClient.Configuration.Realtime(webSocketTransport:)`. See the "Custom Transports"
  article in the Realtime documentation.
- The same transport works for a standalone client: pass it in the `http` setting of the
  configuration of that client.
