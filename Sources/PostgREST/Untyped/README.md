# Untyped

The string-based builders: `PostgrestClient.from(_:)` with a table name, `rpc(_:)`, and the
`PostgrestRequestBuilder` phases. They are the untyped fallback for queries the typed API cannot
express yet, and they are supported.

They build on the shared core. A request is a `_PostgrestRequest` (`Request/`), and it is sent
through `_PostgrestRequest.execute(on:decode:)`. A change to how a request is assembled or sent —
headers, schema profiles, null stripping, retry, error mapping — belongs in the core, so the typed
and untyped paths cannot drift apart. Filters still append query items directly; moving them onto
`_PostgrestFilter` is SDK-2167.
