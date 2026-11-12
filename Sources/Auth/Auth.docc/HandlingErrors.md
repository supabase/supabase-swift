# Handling Errors

Tell a wrong password from a lost session and from a network failure.

## Overview

Every failure from ``AuthClient``, ``AuthMFA`` and ``AuthAdminClient`` is an ``AuthError`` or a
`CancellationError`, except an error that your own code throws. Check ``AuthError/kind`` first. It says which party failed.

| Kind | When | Set |
| --- | --- | --- |
| ``AuthError/Kind-swift.struct/server`` | The Auth server answered with a non-2xx status. | ``AuthError/response``, and usually ``AuthError/code`` |
| ``AuthError/Kind-swift.struct/sessionMissing`` | The call needs a session and none is stored. | ``AuthError/message`` |
| ``AuthError/Kind-swift.struct/sessionInvalidated`` | The server rejected the session or its refresh token. | ``AuthError/code``, ``AuthError/response`` |
| ``AuthError/Kind-swift.struct/oauthFlowFailed`` | A redirect-based sign-in could not start or finish. | ``AuthError/code`` when the URL or the server sent one |
| ``AuthError/Kind-swift.struct/transport`` | No response arrived. | ``AuthError/underlyingError``, usually a `URLError` |
| ``AuthError/Kind-swift.struct/decoding`` | A 2xx body could not be used. | ``AuthError/underlyingError``, the `DecodingError` |
| ``AuthError/Kind-swift.struct/storageUnavailable`` | Session storage cannot be read or written now, for example while the device is locked. | ``AuthError/underlyingError`` |
| ``AuthError/Kind-swift.struct/invalidRequest`` | The SDK refused to send the request. | ``AuthError/underlyingError`` |

``AuthError/Kind-swift.struct`` is an open set and has more members than this table. Keep a
fallback branch.

### Server codes

When the kind is ``AuthError/Kind-swift.struct/server``, ``AuthError/code`` is the
machine-readable code that the server sent. A `catch` clause can name a code or a kind directly:

```swift
do {
  try await supabase.auth.signIn(email: email, password: password)
} catch AuthError.Code.invalidCredentials {
  showWrongPassword()
} catch AuthError.Code.emailNotConfirmed {
  showConfirmEmail()
} catch AuthError.Kind.transport {
  showOfflineBanner()
}
```

- ``AuthError/code`` is `nil` when the server sent no code: an OAuth-style response, a body that
  is not JSON, or a failure that never reached the server.
- ``AuthError/oauthError`` is the raw `error` field of an OAuth-style response, such as
  `invalid_grant`. The ID token grant answers this way.
- ``AuthError/response`` holds the HTTP status, the headers and the body. Its `requestID` is the
  value to quote to Supabase support.

``AuthError/Code-swift.struct`` is an open set too. Compare against the static members, and keep a
fallback branch: a server newer than the SDK can send a code this version does not know.

### Weak passwords

A sign-up or a password change that the server rejects for a weak password has the code
``AuthError/Code-swift.struct/weakPassword``. ``AuthError/weakPasswordReasons`` lists why.

```swift
do {
  try await supabase.auth.updateUser(UpdateUser(password: newPassword))
} catch let error as AuthError where error.code == .weakPassword {
  showReasons(error.weakPasswordReasons)
}
```

### A lost session

``AuthError/Kind-swift.struct/sessionMissing`` means that no session is stored. Sign the user in.

``AuthError/Kind-swift.struct/sessionInvalidated`` means that the server rejected the session: it
expired, was revoked, or the user is banned. When the rejected session is the current one, the
client signs out and emits ``AuthEvent/signedOut``. Do not show the sign-in screen from the
`catch` clause. Follow ``AuthClient/events()`` or an ``AuthModel``, and show it when the state
changes. A rejected refresh while the access token is still valid keeps the session until it
expires.

### Transport failures and retries

A transport failure means no answer arrived, so whether the server applied the request is
unknown. Reads are safe to retry. Before you retry a sign-up or an update, check that it did not
already happen.

The SDK retries `GET` requests for you on a transient error. It retries a token request only
after a connection failure. Turn retries off with ``AuthClient/Configuration/retryEnabled``.

### Cancellation

A cancelled task throws `CancellationError`, never a wrapped error. A user who closes the web
authentication sheet also gives `CancellationError`.

```swift
do {
  try await supabase.auth.signInWithOAuth(.github)
} catch is CancellationError {
  // the user closed the sheet
} catch let error as AuthError {
  log(error.message)
}
```

Errors from your own code reach you as themselves: a custom transport, a middleware, or a custom
``AuthStorage``.
