import CustomDump
import Foundation
import Testing

@testable import Auth

@Suite
struct PersistedSessionCodecTests {
  @Test(arguments: PersistedSessionFixtures.v2Shapes)
  func decodesV2ShapeAndReencodesAsSchema1(fixture: String) throws {
    let decoded = try PersistedSessionCodec.decode(json(named: fixture))

    #expect(!decoded.isCurrentSchema)
    expectNoDifference(decoded.session.session, PersistedSessionFixtures.expectedSession)
    #expect(decoded.session.receivedAt == PersistedSessionFixtures.expectedReceivedAt)

    let reencoded = try PersistedSessionCodec.encode(decoded.session)
    expectNoDifference(
      String(decoding: reencoded, as: UTF8.self),
      String(decoding: json(named: PersistedSessionFixtures.schema1), as: UTF8.self)
    )
  }

  @Test
  func decodesSchema1() throws {
    let decoded = try PersistedSessionCodec.decode(json(named: PersistedSessionFixtures.schema1))

    #expect(decoded.isCurrentSchema)
    expectNoDifference(decoded.session.session, PersistedSessionFixtures.expectedSession)
    #expect(decoded.session.receivedAt == PersistedSessionFixtures.expectedReceivedAt)
  }

  @Test
  func schema1RoundTripsExactly() throws {
    var session = Session.valid
    session.user.lastSignInAt = Date()
    session.user.factors = [
      Factor(
        id: UUID(),
        friendlyName: nil,
        factorType: "totp",
        status: .verified,
        createdAt: Date(),
        updatedAt: Date()
      )
    ]
    session.user.identities?[0].identityData = nil
    let received = ReceivedSession(session: session, receivedAt: Date())

    let decoded = try PersistedSessionCodec.decode(PersistedSessionCodec.encode(received))

    #expect(decoded.isCurrentSchema)
    expectNoDifference(decoded.session, received)
  }

  @Test
  func decodesNanosecondsAndOffsets() throws {
    let decoded = try PersistedSessionCodec.decode(
      json(named: "persisted-session-schema-1-offsets")
    )
    let user = decoded.session.session.user

    #expect(
      decoded.session.receivedAt
        == Date(timeIntervalSinceReferenceDate: 811_766_565 + 0.123_456_789)
    )
    // 2026-09-22T12:42:45.987654321+02:00
    #expect(user.createdAt == Date(timeIntervalSinceReferenceDate: 811_766_565 + 0.987_654_321))
    // 2026-09-22T05:12:45-05:30
    #expect(user.updatedAt == Date(timeIntervalSinceReferenceDate: 811_766_565))
    // 2026-09-22T10:42:45.5Z
    #expect(user.lastSignInAt == Date(timeIntervalSinceReferenceDate: 811_766_565.5))
  }

  @Test
  func schema1WithAMissingFieldFailsInsteadOfFallingBack() {
    let data = Data(
      #"{"schema":1,"received_at":"2026-09-22T10:42:45Z","token_type":"bearer"}"#.utf8
    )

    #expect(throws: DecodingError.self) {
      try PersistedSessionCodec.decode(data)
    }
  }

  @Test(arguments: [
    #"{"schema":2,"access_token":"a"}"#,
    #"{"token":"a"}"#,
    "not-json",
  ])
  func rejectsUnknownData(_ json: String) {
    #expect(throws: DecodingError.self) {
      try PersistedSessionCodec.decode(Data(json.utf8))
    }
  }

  /// Rewrites the v2 fixtures with the encoders v2 used, and the schema 1 golden. Run with
  /// `RECORD_PERSISTED_SESSION_FIXTURES=1` only when a fixture must change; v2 is frozen.
  @Test(
    .enabled(if: ProcessInfo.processInfo.environment["RECORD_PERSISTED_SESSION_FIXTURES"] != nil))
  func recordFixtures() throws {
    struct V2WrappedSession: Encodable {
      var session: Session
      var expirationDate: Date
    }

    let session = PersistedSessionFixtures.v2Session
    let fixtures: [(String, Data)] = [
      ("persisted-session-v2-camel-case", try JSONEncoder().encode(session)),
      (
        "persisted-session-v2-snake-case",
        try AuthClient.Configuration.jsonEncoder.encode(session)
      ),
      (
        "persisted-session-v2-wrapped",
        try AuthClient.Configuration.jsonEncoder.encode(
          V2WrappedSession(
            session: session,
            expirationDate: Date(timeIntervalSince1970: session.expiresAt)
          )
        )
      ),
      (
        PersistedSessionFixtures.schema1,
        try PersistedSessionCodec.encode(
          ReceivedSession(
            session: PersistedSessionFixtures.expectedSession,
            receivedAt: PersistedSessionFixtures.expectedReceivedAt
          )
        )
      ),
    ]

    let resources = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .appendingPathComponent("Resources")
    for (name, data) in fixtures {
      try data.write(to: resources.appendingPathComponent("\(name).json"))
    }
  }
}

enum PersistedSessionFixtures {
  static let v2Shapes = [
    "persisted-session-v2-camel-case",
    "persisted-session-v2-snake-case",
    "persisted-session-v2-wrapped",
  ]
  static let schema1 = "persisted-session-schema-1"

  /// The session as v2 held it in memory when it wrote the fixtures.
  static let v2Session = Session(
    providerToken: "provider-token",
    providerRefreshToken: "provider-refresh-token",
    accessToken: "access-token",
    tokenType: "bearer",
    expiresIn: 3600,
    expiresAt: 1_790_074_965,
    refreshToken: "refresh-token",
    weakPassword: WeakPassword(reasons: ["length", "pwned"]),
    user: User(
      id: UUID(uuidString: "859F402D-B3DE-4105-A1B9-932836D9193B")!,
      appMetadata: ["provider": "email", "providers": ["email", "github"]],
      userMetadata: ["name": "Jane", "referrer_id": nil, "age": 42],
      audience: "authenticated",
      confirmationSentAt: date(1_790_000_000),
      recoverySentAt: date(1_790_000_100),
      emailChangeSentAt: date(1_790_000_200),
      newEmail: "jane.new@example.com",
      invitedAt: date(1_790_000_300),
      actionLink: nil,
      email: "jane@example.com",
      phone: "",
      createdAt: date(1_789_000_000),
      confirmedAt: date(1_790_000_400),
      emailConfirmedAt: date(1_790_000_400),
      phoneConfirmedAt: nil,
      lastSignInAt: date(1_790_071_365),
      role: "authenticated",
      updatedAt: date(1_790_071_365),
      identities: [
        UserIdentity(
          id: "859f402d-b3de-4105-a1b9-932836d9193b",
          identityId: UUID(uuidString: "6C69F399-BE1B-467A-9C53-D3753ABDD2DF")!,
          userId: UUID(uuidString: "859F402D-B3DE-4105-A1B9-932836D9193B")!,
          identityData: ["sub": "859f402d-b3de-4105-a1b9-932836d9193b", "email_verified": true],
          provider: "email",
          createdAt: date(1_789_000_000),
          lastSignInAt: date(1_790_071_365),
          updatedAt: date(1_790_071_365)
        )
      ],
      isAnonymous: false,
      factors: [
        Factor(
          id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
          friendlyName: "Phone",
          factorType: "totp",
          status: .verified,
          createdAt: date(1_789_500_000),
          updatedAt: date(1_789_500_000)
        )
      ]
    )
  )

  /// `v2Session` as v3 decodes it: an empty phone is `nil`.
  static var expectedSession: Session {
    var session = v2Session
    session.user.phone = nil
    return session
  }

  static let expectedReceivedAt = Date(timeIntervalSince1970: 1_790_074_965 - 3600)

  private static func date(_ timeIntervalSince1970: TimeInterval) -> Date {
    Date(timeIntervalSince1970: timeIntervalSince1970)
  }
}
