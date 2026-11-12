# Migrating to v3

Move an app from supabase-swift v2 to v3.

## Overview

v3 changes many public names and some behavior. The full guide is in the repository. It has one
file for the changes that apply to every module, and one file for each module.

| Guide | Covers |
| --- | --- |
| [V3 migration guide](https://github.com/supabase/supabase-swift/blob/main/V3_MIGRATION.md) | How to migrate, changes in every module, and `SupabaseClient` |
| [Auth](https://github.com/supabase/supabase-swift/blob/main/docs/migrations/v3/Auth.md) | `AuthClient`, sessions, OAuth, MFA and session storage |
| [PostgREST](https://github.com/supabase/supabase-swift/blob/main/docs/migrations/v3/PostgREST.md) | Query builders, responses and errors |
| [Storage](https://github.com/supabase/supabase-swift/blob/main/docs/migrations/v3/Storage.md) | `StorageClient`, uploads, downloads and errors |
| [Functions](https://github.com/supabase/supabase-swift/blob/main/docs/migrations/v3/Functions.md) | `FunctionsClient`, bodies, responses and errors |
| [Realtime](https://github.com/supabase/supabase-swift/blob/main/docs/migrations/v3/Realtime.md) | `RealtimeClient`, channels and streams |

### The order of work

1. Install Xcode 26.0 or later.
2. Update the package requirement to v3, then build. Expect many compile errors.
3. Fix the errors from the changes in every module first. Then fix one module at a time. Use the
   "Renames and type changes" table of each guide first, because most errors are a rename.
4. Read each "Silent changes" list. These changes compile, but the behavior is different. The
   compiler does not find them, so search your code for each one.
5. Run your tests, and test the app by hand.

### The largest changes

- Every client initializer throws. Add `try`.
- `SupabaseClientOptions` is ``SupabaseClient/Configuration``, and the initializer label is
  `configuration:`.
- A `ClientTransport` and a list of `ClientMiddleware` replace the `fetch:` closures and the
  custom `URLSession` arguments.
- Each module has one error type with a `kind` and a `code`. `HTTPError` is removed. A network
  error or a decoding error arrives inside the module error, in `underlyingError`.
- A cancelled task throws `CancellationError` in every module.
- Values with a set that can grow are structs, not enums. A `switch` over one needs `default:`.
  See <doc:EnumsAndOpenSets>.
- Every API that v2 marked as deprecated is removed.
