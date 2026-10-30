import Testing

import Auth

@Suite
struct AuthStateTests {
  @Test
  func signOutReasonIsSetOnlyForSignedOutEvent() {
    let signedOut = AuthChange(event: .signedOut, status: .signedOut(.sessionExpired))
    let initial = AuthChange(event: .initialSession, status: .signedOut(.sessionMissing))
    let signedIn = AuthChange(event: .signedIn, status: .signedIn(.valid))

    #expect(signedOut.signOutReason == .sessionExpired)
    #expect(initial.signOutReason == nil)
    #expect(signedIn.signOutReason == nil)
  }

  @Test
  func sessionIsDerivedFromStatus() {
    #expect(AuthChange(event: .signedIn, status: .signedIn(.valid)).session == .valid)
    #expect(AuthChange(event: .initialSession, status: .loading).session == nil)
    #expect(AuthChange(event: .signedOut, status: .signedOut(nil)).session == nil)
  }

  @Test
  func eventsKeepTheirRawValues() {
    let events: [AuthEvent] = [
      .initialSession, .signedIn, .signedOut, .tokenRefreshed, .userUpdated, .passwordRecovery,
      .mfaChallengeVerified,
    ]
    #expect(
      events.map(\.rawValue) == [
        "INITIAL_SESSION", "SIGNED_IN", "SIGNED_OUT", "TOKEN_REFRESHED", "USER_UPDATED",
        "PASSWORD_RECOVERY", "MFA_CHALLENGE_VERIFIED",
      ])
  }
}
