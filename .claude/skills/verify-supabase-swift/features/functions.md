# Functions

An app calls Supabase Edge Functions with `client.functions.invoke`, sends JSON, text, or
bytes, sets the method, query, and region, and decodes the reply or handles an error.

## Sub-features

- `fn-json` sends a JSON body with `Content-Type: application/json` and decodes a typed reply.
- `fn-auth-header` sends no `Authorization` header when the app has no session and uses a
  new-format publishable key.
- `fn-text` sends a text body with `Content-Type: text/plain`.
- `fn-get-query` sends GET to a sub-path with query items and a forced region.
- `fn-missing` throws `FunctionsError` with status 404 for an unknown function.

## How to get to it (user POV)

- `client.functions.invoke(_:body:options:)` with `body: .json(...)`, `.text(...)`, `.data(...)`
- `FunctionInvokeOptions(method:query:region:)`
- `client.functions.stream(_:body:)` for streamed replies (not in the bundled journey)

## Driving it with verify.sh

Preconditions:

- A run from `$V up` is live and `$V doctor` is all `ok` (it calls `functions/echo`).
- The `echo` function from `Tests/IntegrationTests/supabase/functions/echo` returns the method,
  path, query, some headers, and the base64 body of each request.

- **JSON.** Run `$V drive functions`. Step `fn-json` shows `POST /echo`,
  `content-type=application/json`, and the body `{"hello":"verify"}`. It saves `fn-json.json`.
- **Auth header.** Step `fn-auth-header` shows the header absent.
- **Text.** Step `fn-text` shows `plain words` and `text/plain; charset=utf-8`.
- **GET with query and region.** Step `fn-get-query` shows `GET /echo/sub/path`,
  `month=2026-09`, `forceFunctionRegion=eu-west-1`, and `x-region=eu-west-1`.
- **Missing function.** Step `fn-missing` shows `FunctionsError(server)` with status 404.
- **Outside view.** The echo reply is the server's record of the request. The saved
  `fn-*.json` files are that view. Each one is the request as the function received it.

## Gotchas

- `echo` returns only the scheme of `Authorization` (for example `Bearer`), never the token.
- A new-format `sb_publishable_...` key is not a JWT. With no session the SDK sends it only as
  `apikey`. With a signed-in user, `Authorization: Bearer <access token>` is expected. Sign in
  first to check that path.
- `FunctionInvokeOptions.headers` is `HTTPFields`, not `[String: String]`. A journey that sets
  custom headers needs `import HTTPTypes`, which the driver package does not declare.
- The first call to a function after `up` is slow, because the edge runtime boots the worker.
  `up` calls `echo` once, so journeys start warm.
