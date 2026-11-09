import ConcurrencyExtras
import Foundation
import HTTPTypes
import Helpers
import TestHelpers
import Testing

@testable import Auth

@Suite
struct SessionTimingTests {
  private static let received = Date(timeIntervalSince1970: 1_800_000_000)

  private func session(
    expiresIn: Duration = .seconds(3600),
    receivedAt: Date = Self.received,
    expiresAt: Date? = nil
  ) -> Session {
    Session(
      accessToken: "access",
      tokenType: "bearer",
      expiresIn: expiresIn,
      expiresAt: expiresAt ?? receivedAt.addingTimeInterval(expiresIn.timeInterval),
      receivedAt: receivedAt,
      refreshToken: "refresh",
      user: User(fromMockNamed: "user")
    )
  }

  // MARK: - isExpired(at:leeway:)

  @Test
  func aFreshSessionIsNotExpired() {
    #expect(!session().isExpired(at: Self.received))
  }

  @Test
  func isNotExpiredWhenTheRemainingLifetimeEqualsTheLeeway() {
    let at = Self.received.addingTimeInterval(3600 - 30)

    #expect(!session().isExpired(at: at, leeway: .seconds(30)))
  }

  @Test
  func isExpiredOnceTheRemainingLifetimeFallsBelowTheLeeway() {
    let at = Self.received.addingTimeInterval(3600 - 30 + 0.5)

    #expect(session().isExpired(at: at, leeway: .seconds(30)))
  }

  @Test
  func theDefaultLeewayIsThirtySeconds() {
    #expect(!session().isExpired(at: Self.received.addingTimeInterval(3569)))
    #expect(session().isExpired(at: Self.received.addingTimeInterval(3571)))
  }

  @Test
  func aZeroLeewayExpiresAtTheExpiryInstant() {
    let sut = session()

    #expect(!sut.isExpired(at: Self.received.addingTimeInterval(3600), leeway: .zero))
    #expect(sut.isExpired(at: Self.received.addingTimeInterval(3600.5), leeway: .zero))
  }

  @Test
  func aServerExpiryWithinTheSkewToleranceMovesTheExpiryEarlier() {
    let sut = session(expiresAt: Self.received.addingTimeInterval(3590))

    #expect(sut.isExpired(at: Self.received.addingTimeInterval(3565)))
  }

  @Test
  func aServerExpiryBeyondTheSkewToleranceIsIgnored() {
    let sut = session(expiresAt: Self.received.addingTimeInterval(3000))

    #expect(!sut.isExpired(at: Self.received.addingTimeInterval(3000)))
    #expect(sut.isExpired(at: Self.received.addingTimeInterval(3571)))
  }

  // MARK: - Decoding

  @Test
  func decodesExpiresInAsSecondsAndExpiresAtAsUnixSeconds() throws {
    let sut = try AuthClient.Configuration.jsonDecoder.decode(
      Session.self, from: Self.body(expiresIn: "3600", expiresAt: "1700003600"))

    #expect(sut.expiresIn == .seconds(3600))
    #expect(sut.expiresAt == Date(timeIntervalSince1970: 1_700_003_600))
  }

  @Test
  func receivedAtDefaultsToTheServerIssueTime() throws {
    let sut = try AuthClient.Configuration.jsonDecoder.decode(
      Session.self, from: Self.body(expiresIn: "3600", expiresAt: "1700003600"))

    #expect(sut.receivedAt == Date(timeIntervalSince1970: 1_700_000_000))
  }

  @Test
  func decodesAFractionalExpiresIn() throws {
    let sut = try AuthClient.Configuration.jsonDecoder.decode(
      Session.self, from: Self.body(expiresIn: "0.5", expiresAt: "1700000000"))

    #expect(sut.expiresIn == .milliseconds(500))
  }

  @Test(arguments: ["1e30", "-1e30", "1e13"])
  func rejectsAnExpiresInOutOfRangeInsteadOfTrapping(expiresIn: String) {
    #expect(throws: DecodingError.self) {
      try AuthClient.Configuration.jsonDecoder.decode(
        Session.self, from: Self.body(expiresIn: expiresIn, expiresAt: "1700000000"))
    }
  }

  @Test
  func anExpiresAtOutOfRangeDoesNotTrapTheExpiryCheck() throws {
    let sut = try AuthClient.Configuration.jsonDecoder.decode(
      Session.self, from: Self.body(expiresIn: "3600", expiresAt: "1e30"))

    #expect(!sut.isExpired(at: Date(timeIntervalSince1970: 1_700_000_000)))
  }

  @Test
  func encodesWhatItDecodes() throws {
    let original = session(receivedAt: Date(timeIntervalSince1970: 1_700_000_100))

    let data = try AuthClient.Configuration.jsonEncoder.encode(original)
    let decoded = try AuthClient.Configuration.jsonDecoder.decode(Session.self, from: data)

    // The fixture user's dates do not survive a second JSON round trip, so compare the timing.
    #expect(decoded.expiresIn == original.expiresIn)
    #expect(decoded.expiresAt == original.expiresAt)
    #expect(decoded.receivedAt == original.receivedAt)
    #expect(decoded.accessToken == original.accessToken)
  }

  @Test
  func encodesTheServerShape() throws {
    let data = try AuthClient.Configuration.jsonEncoder.encode(session())
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(object["expires_in"] as? Double == 3600)
    #expect(object["expires_at"] as? Double == 1_800_003_600)
  }

  // MARK: - receivedAt comes from configuration.now

  @Test
  func aSessionFromTheServerIsStampedWithConfigurationNow() async throws {
    let now = Date(timeIntervalSince1970: 1_750_000_000)
    let transport = RecordingTransport { _, _ in
      (
        HTTPTypes.HTTPResponse(status: .ok, headerFields: [.contentType: "application/json"]),
        Self.body(expiresIn: "3600", expiresAt: "1750003600")
      )
    }
    let sut = try AuthClient(
      configuration: .init(
        url: clientURL,
        storageKey: uniqueStorageKey(),
        storage: InMemoryAuthStorage(),
        autoRefresh: .manual,
        observesAppLifecycle: false,
        http: .init(transport: transport),
        now: { now }
      )
    )

    let session = try await sut.signIn(email: "user@example.com", password: "secret")

    #expect(session.receivedAt == now)
    #expect(sut.currentSession?.receivedAt == now)
  }

  private static func body(expiresIn: String, expiresAt: String) -> Data {
    var user = String(decoding: json(named: "user"), as: UTF8.self)
    user = user.trimmingCharacters(in: .whitespacesAndNewlines)
    return Data(
      """
      {"access_token":"access","token_type":"bearer","expires_in":\(expiresIn),\
      "expires_at":\(expiresAt),"refresh_token":"refresh","user":\(user)}
      """.utf8)
  }
}
