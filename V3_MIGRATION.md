# V3 Migration Guide

This document describes the breaking changes you need to be aware of when upgrading to v3 of the
Supabase Swift SDK, together with the steps required to migrate your code. All modules
(`Auth`, `Storage`, `Realtime`, `PostgREST`, `Functions`, `Supabase`) are covered here.

> [!NOTE]
> v3 has not been released yet. This document is updated as breaking changes land on `main`, so
> treat it as the running list rather than the final one.

## `verifyOTP` now returns `VerifyOTPResponse` instead of `AuthResponse`

`verifyOTP` and its overloads return a new `VerifyOTPResponse` type instead of `AuthResponse`.

GoTrue's `/verify` endpoint returns a body with only `{ msg, code }` for the first of the two
confirmations required by a secure email change — a shape `AuthResponse` can't represent, since it
only ever holds a `Session` or a `User`. That made `verifyOTP(type: .emailChange)` throw a
`DecodingError` instead of completing successfully. `AuthResponse` is also the return type of
`signUp` and the Passkey methods, neither of which can ever produce that shape, so growing it to
fit `verifyOTP` would have meant every caller of those unrelated methods handling a case only one
specific call can trigger.

`VerifyOTPResponse` only has the two shapes `verifyOTP` can actually return:

```swift
public enum VerifyOTPResponse {
  case session(Session)
  case emailChangeConfirmationPending(EmailChangeConfirmation)
}
```

`EmailChangeConfirmation` carries the `message`/`code` GoTrue sends for that first confirmation.
There's no bare-`User` case here — succeeding at `/verify` always means either a session was
issued or the other email still needs to confirm; unlike `signUp`, it can never leave you with a
user and no session.

This is a compile error, not a silent behavior change: the return type itself changed, so every
call site using the result needs updating.

```swift
// Before
let response: AuthResponse = try await client.verifyOTP(tokenHash: hash, type: .emailChange)
let email = response.user?.email

// After
let response: VerifyOTPResponse = try await client.verifyOTP(tokenHash: hash, type: .emailChange)
let email = response.session?.user.email
```

`AuthResponse` itself is unchanged: `signUp` and the Passkey methods still return it, and `user` is
still non-optional there, since neither endpoint can produce the confirmation-pending shape.
