# Auth

An app signs a user up and in with email and password, reads the current session, signs out,
and observes auth events through `client.auth`.

## Sub-features

- `auth-signup` signs up with email, password, and metadata, and gets a session at once.
- `auth-metadata` keeps the sign-up metadata in `user.userMetadata`.
- `auth-session` reads the stored session for the signed-in user.
- `auth-signout` signs out; reading the session then throws `AuthError` of kind
  `sessionMissing`.
- `auth-signin` signs in again with the same credentials.
- `auth-events` emits `INITIAL_SESSION`, `SIGNED_IN`, `SIGNED_OUT`, `SIGNED_IN` in order.

## How to get to it (user POV)

- `client.auth.signUp(email:password:options:)`
- `client.auth.session`
- `client.auth.signOut()`
- `client.auth.signIn(email:password:)`
- `client.auth.authStateChanges`

## Driving it with verify.sh

Preconditions:

- A run from `$V up` is live and `$V doctor` is all `ok`.
- `auth.email.enable_confirmations = false` in the run's `supabase/config.toml` (the copy from
  the integration project has it).

- **Sign up.** Run `$V drive auth`. Step `auth-signup` passes with a user id and
  `session=true`, and saves `auth-signup-user.json`. The transcript prints `EMAIL <address>`.
- **Metadata.** Step `auth-metadata` shows `"source": verify` in `user_metadata`.
- **Session.** Step `auth-session` shows the same email and an expiry.
- **Sign out.** Step `auth-signout` passes when reading the session throws `sessionMissing`.
- **Sign in.** Step `auth-signin` shows the same email.
- **Events.** Step `auth-events` saves `auth-events.json` with the four events in order.
- **Outside view.** Run `$V http GET "/auth/v1/admin/users?per_page=50"`. The body lists the
  journey's email with `user_metadata.source == "verify"`. Save it as `admin-users.http.txt`.

## Gotchas

- `client.auth.session` throws after sign-out. It does not return `nil`. A journey that wraps
  it in `Verify.attempt` reports a false `FAIL`.
- `authStateChanges` emits `INITIAL_SESSION` as soon as a listener starts. Start the listener
  before the first auth call, or the order differs.
- `Verify.client()` stores the session in memory. The Keychain store is not covered. To verify
  Keychain behavior, run the Examples app on a simulator.
- The stack rate-limits sign-ups and sign-ins (`auth.rate_limit.sign_in_sign_ups = 30` in the
  config). Many reruns in a short time fail with HTTP 429. Wait, or start a new run.
- OTP, magic link, and email change send mail to Mailpit (`SUPABASE_MAILPIT_URL` in
  `.verify/runs/<run-id>/state.env`). Read the code from Mailpit's API. Nothing leaves the
  machine.
- OAuth sign-in needs a browser redirect. This harness does not cover it.
