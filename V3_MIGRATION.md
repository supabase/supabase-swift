# V3 Migration Guide

This document describes the breaking changes you need to be aware of when upgrading to v3 of the
Supabase Swift SDK, together with the steps required to migrate your code. All modules
(`Auth`, `Storage`, `Realtime`, `PostgREST`, `Functions`, `Supabase`) are covered here.

> [!NOTE]
> v3 has not been released yet. This document is updated as breaking changes land on `main`, so
> treat it as the running list rather than the final one.

## `AuthResponse.user` is now optional

`AuthResponse.user` is `User?` instead of `User`, and `AuthResponse` gained a new `.none` case.

GoTrue's `/verify` endpoint returns a body with only `{ msg, code }` for the first of the two
confirmations required by a secure email change. `AuthResponse` could previously only decode a
`Session` or a `User`, so this shape made `verifyOTP(type: .emailChange)` throw a `DecodingError`
instead of completing successfully. `AuthResponse` now has a `.none` case for this shape, and
`user` returns `nil` for it.

This is a compile error, not a silent behavior change: any call site that reads `response.user`
directly fails to build until you handle the optional.

```swift
// Before
let email = response.user.email

// After
let email = response.user?.email
```

This affects the return value of any `AuthClient` method that returns `AuthResponse`, including
`signUp` and `verifyOTP`. `Session.user` is unaffected and remains `User` (non-optional).
