# Handling Errors

Tell a constraint violation from a network failure, and read what the database reported.

## Overview

Every failure from a PostgREST call is a ``PostgrestError`` or a `CancellationError`. Check
``PostgrestError/kind`` first.

| Kind | When | Set |
| --- | --- | --- |
| ``PostgrestError/Kind-swift.struct/server`` | PostgREST answered with a non-2xx status. | ``PostgrestError/response``, and usually ``PostgrestError/code`` and ``PostgrestError/serverError`` |
| ``PostgrestError/Kind-swift.struct/transport`` | No response arrived. | ``PostgrestError/underlyingError``, usually a `URLError` |
| ``PostgrestError/Kind-swift.struct/decoding`` | A 2xx body could not be used, for example rows that do not match your type. | ``PostgrestError/underlyingError``, the `DecodingError` |
| ``PostgrestError/Kind-swift.struct/invalidRequest`` | The SDK refused to send the request. | ``PostgrestError/message`` |
| ``PostgrestError/Kind-swift.struct/accessToken`` | The access token provider threw. Nothing was sent. | ``PostgrestError/underlyingError``, the provider's error |

``PostgrestError/Kind-swift.struct`` is an open set. Keep a fallback branch.

### Database codes

``PostgrestError/code`` is the code in the error body. It is a PostgreSQL `SQLSTATE`, such as
`23505`, or a PostgREST code, such as `PGRST116`. A `catch` clause can name a code or a kind
directly:

```swift
do {
  try await supabase.from("todos").insert(todo).execute()
} catch PostgrestError.Code.uniqueViolation {
  showDuplicate()
} catch let error as PostgrestError where error.code == .foreignKeyViolation {
  showMissingParent(error.serverError?.details)
} catch PostgrestError.Kind.transport {
  showOfflineBanner()
}
```

- ``PostgrestError/Code-swift.struct`` has static members for common PostgreSQL codes. Compare
  any other code with a string literal: `error.code == "PGRST116"`. It is an open set, so keep a
  fallback branch.
- ``PostgrestError/serverError`` is the rest of the body: `message`, `details` and `hint`. It is
  `nil` when the body was not a PostgREST error payload, for example a page from a proxy.
- ``PostgrestError/response`` holds the HTTP status, the headers and the body. Its `requestID`
  is the value to quote to Supabase support.

### No row, or more than one

``PostgrestRequestBuilder/single()`` throws when the result is not exactly one row. The code is
`PGRST116`. To get `nil` for no row, use ``PostgrestRequestBuilder/maybeSingle()`` and decode
an optional.

```swift
let todo: Todo? = try await supabase.from("todos")
  .select()
  .eq("id", value: id)
  .maybeSingle()
  .execute()
  .value
```

### Row level security

A `select` that a policy blocks is not an error. It returns no rows. An `update` or a `delete`
of rows that the user cannot see is not an error either. It changes no rows. An `insert`, or an
`update` whose new row fails a policy check, throws with the code
``PostgrestError/Code-swift.struct/insufficientPrivilege``.

### Transport failures and retries

A transport failure means no answer arrived, so whether the database applied the request is
unknown. Reads are safe to retry. Before you retry a write, check that it did not already happen.

The SDK retries `GET` and `HEAD` requests for you, up to three retries (four attempts) with jittered backoff.
It never replays a write. Turn retries off with
``PostgrestClient/Configuration/retryEnabled``, or for one request with
``PostgrestRequestBuilder/retry(enabled:)``.

### Cancellation

A cancelled task throws `CancellationError`, never a wrapped error.

Errors from your own code inside the exchange, such as a custom transport or a middleware, reach
you as themselves. An error from the access token provider is a ``PostgrestError`` with kind
``PostgrestError/Kind-swift.struct/accessToken``.
