## AuthResponse Migration Guide

Starting in this release, `AuthResponse.user` is `User?` instead of `User`, and `AuthResponse`
gained a new `.none` case.

### Why this changed

GoTrue's `/verify` endpoint returns a body with only `{ msg, code }` for the first of the two
confirmations required by a secure email change. `AuthResponse` could previously only decode a
`Session` or a `User`, so this shape made `verifyOTP(type: .emailChange)` throw a `DecodingError`
instead of completing successfully.

`AuthResponse` now has a `.none` case for this shape, and `user` returns `nil` for it.

### Updating your code

Any call site that reads `response.user` directly must now handle the optional:

```swift
// Before
let email = response.user.email

// After
let email = response.user?.email
```

This affects the return value of any `AuthClient` method that returns `AuthResponse`, including
`signUp` and `verifyOTP`.

`Session.user` is unaffected and remains `User` (non-optional).
