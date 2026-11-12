# ``Auth``

Sign users in and out, keep their session, and follow the auth state of your app.

## Overview

``AuthClient`` is the client for the `/auth/v1` API. Get one from `supabase.auth`. It signs users
in, holds the session in storage, refreshes it, and reports every change of the auth state.

Read the current state with ``AuthClient/status``. Follow every change with
``AuthClient/events()``. In SwiftUI, let an ``AuthModel`` do that for you (see
<doc:ObservingAuthStateInSwiftUI>).

Every failure is an ``AuthError`` or a `CancellationError`, except an error that your own code
throws. See <doc:HandlingErrors>.

## Topics

### Essentials

- <doc:AuthAndSwiftConcurrency>
- <doc:ObservingAuthStateInSwiftUI>
- <doc:HandlingRedirectsAndDeepLinks>
- <doc:SharingASessionWithAnAppExtension>
- <doc:ImportingASessionOnTvOS>
- <doc:HandlingErrors>
- <doc:Standalone>

### Client

- ``AuthClient``
- ``AuthClient/Configuration``
- ``AuthAdminClient``

### Auth State

- ``AuthStatus``
- ``AuthChange``
- ``AuthEvent``
- ``SignOutReason``
- ``AuthModel``

### Sessions and Users

- ``Session``
- ``User``
- ``UserIdentity``
- ``VerifiedClaims``

### Session Storage

- ``AuthStorage``
- ``KeychainStorage``
- ``InMemoryAuthStorage``

### Multi-Factor Authentication

- ``AuthMFA``
- ``Factor``
- ``AuthenticatorAssuranceLevel``

### Errors

- ``AuthError``
