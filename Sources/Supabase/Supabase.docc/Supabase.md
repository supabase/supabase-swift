# ``Supabase``

One client for a Supabase project: Auth, the database, Storage, Edge Functions and Realtime.

## Overview

``SupabaseClient`` connects the modules of the SDK. Create one client for your app and keep it.
It sends the signed-in user's token with every request, and gives Realtime a new token when the
session changes.

```swift
import Supabase

let supabase = try SupabaseClient(
  supabaseURL: URL(string: "https://<ref>.supabase.co")!,
  supabaseKey: "sb_publishable_…"
)
```

Each product is one property or one method of the client:

| Product | Entry point | Module |
| --- | --- | --- |
| Auth | ``SupabaseClient/auth`` | `Auth` |
| Database | ``SupabaseClient/from(_:)``, ``SupabaseClient/rpc(_:params:count:)`` | `PostgREST` |
| Storage | ``SupabaseClient/storage`` | `Storage` |
| Edge Functions | ``SupabaseClient/functions`` | `Functions` |
| Realtime | ``SupabaseClient/realtime``, ``SupabaseClient/channel(_:configure:)`` | `Realtime` |

`import Supabase` brings in the types of every module. Each module also works on its own; see
the "Standalone Use" article in the documentation of that module.

Every client initializer and every request can throw. Each module has one error type, and all
of them conform to `SupabaseError`.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:TestingWithAStubTransport>
- <doc:EnumsAndOpenSets>
- <doc:MigratingToV3>

### Client

- ``SupabaseClient``
- ``SupabaseClient/Configuration``

### Errors

- ``SupabaseClientError``
