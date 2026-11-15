# Importing a Session on tvOS

Sign in a device that has no keyboard by moving a session from another device.

## Overview

A TV has no good way to type a password. A common design is to sign the user in on a phone or on
the web, and to give the TV the tokens of that session. Auth does not carry the tokens for you.
Your app, or your backend, moves them. Once the TV has them, call
``AuthClient/importSession(accessToken:refreshToken:)``. The same call works on watchOS, and
wherever else your app receives a session from outside the client.

### Import the tokens

```swift
func receive(accessToken: String, refreshToken: String) async {
  do {
    let session = try await supabase.auth.importSession(
      accessToken: accessToken,
      refreshToken: refreshToken
    )
    print("Signed in as \(session.user.id)")
  } catch {
    showError(error)
  }
}
```

The client reads the expiry from the access token, then does one of two things:

- When the token has expired, it redeems the refresh token for a new session.
- Otherwise, it fetches the user with the access token.

Then it stores the session and emits ``AuthEvent/signedIn`` once. A view that follows
<doc:ObservingAuthStateInSwiftUI> updates at once. When a request fails, the stored session stays as
it was.

The call throws an ``AuthError`` of kind ``AuthError/Kind-swift.struct/jwtVerificationFailed``
when the access token is not a JWT with an `exp` claim. The client does not check the signature
itself. Whether the server checks it depends on the branch:

- With an access token that has not expired, the call sends the access token to fetch the user.
  The server checks the signature, so a forged token makes the call throw.
- With an expired access token, the call sends only the refresh token. The server never sees the
  access token, so a forged expired token with a valid refresh token does not make the call throw.
  The session that the server returns replaces the token.

### Keep the tokens safe

The tokens are credentials. Send them only over a secure channel, and do not log them. Do not let
the sending device keep using the same session. A refresh token rotates, and two devices that
refresh the same one race, so the server can revoke the session. Sign the user in again on the
sending side, or give each device its own session.

### Present a sign-in page when the device has a browser

``ASWebAuthenticationSessionPresenter`` runs on tvOS and watchOS. Test the flow on a device before
you ship it. On tvOS the system cannot close the page for the app. When the task that awaits the
sign-in is cancelled, the call throws at once and the page stays until the user dismisses it. For a
TV, importing a session is the more reliable path.
