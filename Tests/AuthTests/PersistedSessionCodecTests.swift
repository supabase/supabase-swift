import CustomDump
import Foundation
import Testing

@testable import Auth

@Suite
struct PersistedSessionCodecTests {
  @Test(arguments: PersistedSessionFixtures.v2Shapes)
  func decodesV2ShapeAndReEncodesAsSchema1(fixture: String) throws {
    let decoded = try PersistedSessionCodec.decode(json(named: fixture))

    #expect(!decoded.isCurrentSchema)
    expectNoDifference(decoded.session, PersistedSessionFixtures.expectedSession)
    #expect(decoded.session.receivedAt == PersistedSessionFixtures.expectedReceivedAt)

    let reEncoded = try PersistedSessionCodec.encode(decoded.session)
    expectNoDifference(
      String(decoding: reEncoded, as: UTF8.self),
      String(decoding: json(named: PersistedSessionFixtures.schema1), as: UTF8.self)
    )
  }

  /// v2 stored metadata keys verbatim: Foundation applies no key strategy to `[String: _]` keys.
  @Test(arguments: PersistedSessionFixtures.v2Shapes)
  func keepsV2MetadataKeysVerbatim(fixture: String) throws {
    let original = String(decoding: try json(named: fixture), as: UTF8.self)
    let mixedKeys = original.replacingOccurrences(
      of: #""referrer_id":null"#,
      with: #""referrer_id":null,"signupSource":"ios","_private_":{"nested_key":1}"#
    )
    try #require(mixedKeys != original)

    let decoded = try PersistedSessionCodec.decode(Data(mixedKeys.utf8))

    expectNoDifference(
      decoded.session.user.userMetadata,
      [
        "name": "Jane", "referrer_id": nil, "age": 42, "signupSource": "ios",
        "_private_": ["nested_key": 1],
      ]
    )
  }

  @Test
  func decodesSchema1() throws {
    let decoded = try PersistedSessionCodec.decode(json(named: PersistedSessionFixtures.schema1))

    #expect(decoded.isCurrentSchema)
    expectNoDifference(decoded.session, PersistedSessionFixtures.expectedSession)
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
    session.user.identities?[0].identityData = [:]
    session.user.identities?[0].email = "jane@example.com"
    session.user.actionLink = URL(string: "https://example.com/auth/v1/verify?token=t&type=signup")
    let decoded = try PersistedSessionCodec.decode(PersistedSessionCodec.encode(session))

    #expect(decoded.isCurrentSchema)
    expectNoDifference(decoded.session, session)
  }

  @Test(arguments: PersistedSessionFixtures.v2Shapes + [PersistedSessionFixtures.schema1])
  func identityIDsMapAfterReshape(fixture: String) throws {
    let decoded = try PersistedSessionCodec.decode(json(named: fixture))
    let identity = try #require(decoded.session.user.identities?.first)

    #expect(identity.id == UUID(uuidString: "6C69F399-BE1B-467A-9C53-D3753ABDD2DF"))
    #expect(identity.providerUserID == "859f402d-b3de-4105-a1b9-932836d9193b")
    #expect(identity.userID == UUID(uuidString: "859F402D-B3DE-4105-A1B9-932836D9193B"))
    #expect(identity.provider == .email)
  }

  @Test
  func schema1WithAMissingFieldFailsInsteadOfFallingBack() {
    let data = Data(
      #"{"schema":1,"received_at":811766565,"token_type":"bearer"}"#.utf8
    )

    #expect(throws: DecodingError.self) {
      try PersistedSessionCodec.decode(data)
    }
  }

  @Test
  func schema1WithAnExpiresInOutOfRangeFailsInsteadOfTrapping() throws {
    let valid = String(
      decoding: try PersistedSessionCodec.encode(Session.valid), as: UTF8.self)
    let corrupt = valid.replacingOccurrences(of: #""expires_in":120"#, with: #""expires_in":1e30"#)
    try #require(corrupt != valid)

    #expect(throws: DecodingError.self) {
      try PersistedSessionCodec.decode(Data(corrupt.utf8))
    }
  }

  @Test
  func rejectsANewerSchemaWithoutCallingItCorrupt() {
    #expect(throws: PersistedSessionCodec.NewerSchema(schema: 2)) {
      try PersistedSessionCodec.decode(Data(#"{"schema":2,"access_token":"a"}"#.utf8))
    }
  }

  @Test(arguments: [
    #"{"schema":0,"access_token":"a"}"#,
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
            expirationDate: session.expiresAt
          )
        )
      ),
      (
        PersistedSessionFixtures.schema1,
        try PersistedSessionCodec.encode(PersistedSessionFixtures.expectedSession)
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
    expiresIn: .seconds(3600),
    expiresAt: Date(timeIntervalSince1970: 1_790_074_965),
    receivedAt: Date(timeIntervalSince1970: 1_790_074_965 - 3600),
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
          id: UUID(uuidString: "6C69F399-BE1B-467A-9C53-D3753ABDD2DF")!,
          providerUserID: "859f402d-b3de-4105-a1b9-932836d9193b",
          userID: UUID(uuidString: "859F402D-B3DE-4105-A1B9-932836D9193B")!,
          provider: .email,
          identityData: ["sub": "859f402d-b3de-4105-a1b9-932836d9193b", "email_verified": true],
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
