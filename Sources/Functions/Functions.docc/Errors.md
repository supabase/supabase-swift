# Errors

Tell a function's failure from the platform's, a lost connection from a cancelled task.

## Overview

Every failure from ``FunctionsClient`` is a ``FunctionsError`` or a `CancellationError`. Check
``FunctionsError/kind`` first.

| Kind | When | ``FunctionsError/response`` | ``FunctionsError/underlyingError`` |
| --- | --- | --- | --- |
| ``FunctionsError/Kind-swift.struct/relay`` | The gateway could not run the function (`x-relay-error: true`). Your code never ran. | set | `nil` |
| ``FunctionsError/Kind-swift.struct/server`` | A non-2xx status with no relay header. | set | `nil` |
| ``FunctionsError/Kind-swift.struct/transport`` | No response arrived. Whether the function ran is unknown. | `nil` | the `URLError` |
| ``FunctionsError/Kind-swift.struct/decoding`` | A 2xx body did not decode as the requested type. | `nil` | the `DecodingError` |
| ``FunctionsError/Kind-swift.struct/invalidRequest`` | The body could not be encoded. Nothing was sent. | `nil` | the `EncodingError` |

The relay check runs before the status check, because a relay failure is a non-2xx status too.

### Platform or function?

A 503 can come from a worker that failed to boot or from your function answering 503. The
platform sets the `sb-error-code` header on every failure it produces, and ``FunctionsError/code``
reads it. ``FunctionsError/isPlatformError`` is `true` for every code but
``FunctionsError/Code-swift.struct/edgeFunctionError``, the tag the gateway adds to your
function's own 5xx.

```swift
do {
  try await supabase.functions.invoke("flaky")
} catch let error as FunctionsError where error.kind == .server {
  if error.isPlatformError {
    log("platform \(error.code?.rawValue ?? "?") status \(error.response?.statusCode ?? 0)")
  } else if let body = error.response?.body {
    let problem = try? JSONDecoder().decode(Problem.self, from: body)
  }
} catch is CancellationError {
  // the user navigated away
}
```

``FunctionsError/Code-swift.struct`` is an open set. Compare against the static members
(``FunctionsError/Code-swift.struct/notFound``, ``FunctionsError/Code-swift.struct/bootError``,
``FunctionsError/Code-swift.struct/idleTimeout``, and the rest) and keep a fallback branch.

### The error body

``FunctionsError/response`` carries the status, every header and the body for `relay` and
`server`. The body is capped at 1 MiB: a function that streams an unbounded error cannot hold
the call open or exhaust memory. The prefix survives. `response.requestID` is the gateway's
`sb-request-id`, the value to quote to Supabase support.

### Cancellation

A cancelled task throws `CancellationError` from `invoke`, from `stream`, and from a loop over
``FunctionStreamResponse/body``. It is never wrapped. A `URLError(.cancelled)` with no task
cancellation behind it, such as a middleware cancelling the request, stays `.transport`. A
timeout is `.transport` with `URLError(.timedOut)`.

### Retrying

The SDK never retries an invocation: an invoke is a `POST` with side effects the SDK cannot
know about. `transport` failures are the ones where the function may still have run, so retry
only when the function is idempotent.
