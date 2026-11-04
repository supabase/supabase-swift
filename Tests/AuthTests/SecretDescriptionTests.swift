import Foundation
import Testing

@testable import Auth

@Suite
struct SecretDescriptionTests {
  static let session = Session(
    providerToken: "provider-token-secret",
    providerRefreshToken: "provider-refresh-secret",
    accessToken: "access-token-secret",
    tokenType: "bearer",
    expiresIn: 3600,
    expiresAt: 4_102_444_800,
    refreshToken: "refresh-token-secret",
    user: User(fromMockNamed: "user")
  )

  static let secrets = [
    "provider-token-secret", "provider-refresh-secret", "access-token-secret",
    "refresh-token-secret",
  ]

  private func expectNoSecrets(
    _ rendered: String, sourceLocation: SourceLocation = #_sourceLocation
  ) {
    for secret in Self.secrets {
      #expect(
        !rendered.contains(secret), "\(secret) leaked into: \(rendered)",
        sourceLocation: sourceLocation)
    }
  }

  @Test
  func sessionDescribesItselfByUserAndExpiryOnly() {
    let session = Self.session
    #expect(
      session.description == "Session(user_id: \(session.user.id), expires_at: 4102444800.0)")
  }

  @Test
  func everyWayToPrintASessionIsMasked() {
    let session = Self.session
    expectNoSecrets("\(session)")
    expectNoSecrets(String(describing: session))
    expectNoSecrets(String(reflecting: session))
    expectNoSecrets(String(describing: Optional(session)))
    expectNoSecrets("\([session])")
  }

  @Test
  func authChangeDescribesTheEventAndTheMaskedStatus() {
    let change = AuthChange(event: .signedIn, status: .signedIn(Self.session))

    expectNoSecrets("\(change)")
    #expect(change.description.contains("signedIn"))
    #expect(change.description.contains(Self.session.user.id.uuidString))
  }

  @Test
  func authStatusInsideAnyContainerIsMasked() {
    expectNoSecrets("\(AuthStatus.signedIn(Self.session))")
    expectNoSecrets("\(ReceivedSession(session: Self.session))")
  }

  @Test
  func signedOutChangeKeepsItsReason() {
    let change = AuthChange(event: .signedOut, status: .signedOut(.sessionExpired))
    #expect(change.description.contains("signedOut"))
    #expect(change.description.contains("sessionExpired"))
  }

  @Test
  func pendingFlowRecordOmitsTheVerifier() {
    let record = PendingFlowRecord(
      id: UUID(),
      verifier: "pkce-verifier-secret",
      purpose: .signIn,
      redirectTo: URL(string: "myapp://callback?state=abc"),
      createdAt: Date(timeIntervalSince1970: 0)
    )

    #expect(!"\(record)".contains("pkce-verifier-secret"))
    #expect("\(record)".contains("sign_in"))
    #expect(!"\(record)".contains("state=abc"))
  }
}
