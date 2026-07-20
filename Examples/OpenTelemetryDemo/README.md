# OpenTelemetry Trace Propagation Demo

Standalone SwiftPM executable showing `SupabaseClient` attach a W3C `traceparent`
header to an outgoing request, and prints the exported OpenTelemetry span next
to it so you can compare the trace/span IDs.

No live Supabase project is needed — requests are intercepted locally and
answered with a canned response, so the focus stays on the header itself.

## Run

```sh
cd Examples/OpenTelemetryDemo
swift run
```

## What to look for

```
→ GET https://example.supabase.co/rest/v1/todos?select=%2A
  traceparent: 00-fd9030a4af14666aafe0c953054e41d1-013e5811ac84e366-01

Compare the traceId/spanId above with the exported span below.

Span list-todos:
TraceId: fd9030a4af14666aafe0c953054e41d1
SpanId: 013e5811ac84e366
...
```

The `traceparent`'s `<trace-id>-<span-id>` segment matches the exported span's
`TraceId`/`SpanId` exactly — proof the header comes from the active span.

## How it's wired

`Package.swift` enables the `OpenTelemetry` trait on the local `supabase-swift`
dependency — that's the only opt-in required:

```swift
.package(path: "../../", traits: ["OpenTelemetry"])
```

With the trait enabled, `SupabaseClient` automatically attaches `traceparent`
to every request while a span is active — no additional client configuration.
See `main.swift`.
