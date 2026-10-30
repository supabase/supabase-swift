// Journey: Auth — email sign-up, session, sign-out, sign-in, and the auth event stream.
// Proof: the SDK's session and events, plus `verify.sh http GET /auth/v1/admin/users` showing the
// user this run created.
import Foundation
import Supabase

let client = Verify.client()
let email = "\(Verify.unique("user"))@example.com"
let password = "verify-\(UUID().uuidString.prefix(12))"

let events = Task { @MainActor in
  var seen: [String] = []
  for await change in client.auth.authStateChanges {
    seen.append(change.event.rawValue)
    if seen.count == 4 { break }
  }
  return seen
}

Verify.step("auth-signup", "sign up \(email) with metadata source=verify")
if let response = await Verify.attempt("auth-signup", {
  try await client.auth.signUp(
    email: email, password: password, options: SignUpOptions(userMetadata: ["source": "verify"]))
}) {
  Verify.save("auth-signup-user.json", response.user)
  Verify.check(
    "auth-signup", response.session != nil && response.user.email == email,
    "user \(response.user.id) session=\(response.session != nil)")
  Verify.check(
    "auth-metadata", response.user.userMetadata["source"] == "verify",
    "user_metadata \(response.user.userMetadata)")
}

Verify.step("auth-session", "read the current session")
if let session = await Verify.attempt("auth-session", { try await client.auth.session }) {
  Verify.check(
    "auth-session", session.user.email == email && !session.accessToken.isEmpty,
    "session for \(session.user.email ?? "nil"), expires \(session.expiresAt)")
}

Verify.step("auth-signout", "sign out")
_ = await Verify.attempt("auth-signout") { try await client.auth.signOut() }
do {
  let stale = try await client.auth.session
  Verify.check("auth-signout", false, "session still present for \(stale.user.email ?? "nil")")
} catch let error as AuthError where error.kind == .sessionMissing {
  Verify.check("auth-signout", true, "reading the session throws sessionMissing")
} catch {
  Verify.check("auth-signout", false, "unexpected error \(String(reflecting: error))")
}

Verify.step("auth-signin", "sign in again with email and password")
if let session = await Verify.attempt("auth-signin", {
  try await client.auth.signIn(email: email, password: password)
}) {
  Verify.check("auth-signin", session.user.email == email, "signed in as \(session.user.email ?? "nil")")
}

Verify.step("auth-events", "collect the first four auth events")
if let seen = await Verify.attempt("auth-events", {
  try await Verify.within(seconds: 5) {
    await withTaskCancellationHandler { await events.value } onCancel: { events.cancel() }
  }
}) {
  Verify.save("auth-events.json", seen)
  Verify.check(
    "auth-events", seen == ["INITIAL_SESSION", "SIGNED_IN", "SIGNED_OUT", "SIGNED_IN"],
    "events \(seen)")
}

print("EMAIL \(email)")
Verify.finish()
