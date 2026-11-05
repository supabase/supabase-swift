# ``Auth``

Sign users in and out, keep their session, and follow the auth state of your app.

## Overview

``AuthClient`` is the client for the `/auth/v1` API. Get one from `supabase.auth`. It signs users
in, holds the session in storage, refreshes it, and reports every change of the auth state.

Read the current state with ``AuthClient/status``. Follow every change with
``AuthClient/events()``. In SwiftUI, let an ``AuthModel`` do that for you (see
<doc:ObservingAuthStateInSwiftUI>).

## Topics

### Essentials

- <doc:AuthAndSwiftConcurrency>
- <doc:ObservingAuthStateInSwiftUI>

### Guides

- <doc:HandlingRedirectsAndDeepLinks>
- <doc:SharingASessionWithAnAppExtension>
- <doc:ImportingASessionOnTvOS>

### Client

- ``AuthClient``

### Auth state

- ``AuthStatus``
- ``AuthChange``
- ``AuthEvent``
- ``SignOutReason``
- ``AuthModel``
