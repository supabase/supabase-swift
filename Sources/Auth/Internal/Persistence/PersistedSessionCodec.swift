import Foundation

/// Reads every stored session format and writes schema 1.
///
/// This is the one place that knows the formats. v2 stored the synthesized `Session` coding in
/// three shapes, told apart here by their keys:
///
/// - camelCase keys and `Date` as seconds since 2001, from `JSONEncoder()`.
/// - snake_case keys and ISO 8601 dates, from `AuthClient.Configuration.jsonEncoder`.
/// - That snake_case session wrapped as `{"session": …, "expiration_date": …}`.
enum PersistedSessionCodec {
  struct Decoded {
    var session: ReceivedSession
    /// `false` when the data is a v2 shape that the caller should rewrite as schema 1.
    var isCurrentSchema: Bool
  }

  static func decode(_ data: Data) throws -> Decoded {
    switch try JSONDecoder().decode(Shape.self, from: data) {
    case .schema(PersistedSession.currentSchema):
      let persisted = try PersistedJSON.decoder.decode(PersistedSession.self, from: data)
      return Decoded(session: persisted.receivedSession, isCurrentSchema: true)

    case .schema(let schema):
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: [PersistedSession.CodingKeys.schema],
          debugDescription: "Unsupported stored session schema \(schema)."
        )
      )

    case .v2Wrapped:
      let wrapped = try v2SnakeCaseDecoder.decode(V2WrappedSession.self, from: data)
      return Decoded(session: ReceivedSession(session: wrapped.session), isCurrentSchema: false)

    case .v2SnakeCase:
      let session = try v2SnakeCaseDecoder.decode(Session.self, from: data)
      return Decoded(session: ReceivedSession(session: session), isCurrentSchema: false)

    case .v2CamelCase:
      let session = try JSONDecoder().decode(Session.self, from: data)
      return Decoded(session: ReceivedSession(session: session), isCurrentSchema: false)
    }
  }

  static func encode(_ session: ReceivedSession) throws -> Data {
    try PersistedJSON.encoder.encode(PersistedSession(session))
  }

  /// The v2 `AuthClient.Configuration.jsonDecoder`, kept here so the v2 shapes stay readable
  /// after that configuration changes.
  private static let v2SnakeCaseDecoder: JSONDecoder = {
    let decoder = JSONDecoder.supabase()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }()

  private struct V2WrappedSession: Decodable {
    var session: Session
  }

  private enum Shape: Decodable {
    case schema(Int)
    case v2Wrapped
    case v2SnakeCase
    case v2CamelCase

    private enum CodingKeys: String, CodingKey {
      case schema
      case session
      case snakeCaseAccessToken = "access_token"
      case camelCaseAccessToken = "accessToken"
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      if container.contains(.schema) {
        self = .schema(try container.decode(Int.self, forKey: .schema))
      } else if container.contains(.session) {
        self = .v2Wrapped
      } else if container.contains(.snakeCaseAccessToken) {
        self = .v2SnakeCase
      } else if container.contains(.camelCaseAccessToken) {
        self = .v2CamelCase
      } else {
        throw DecodingError.dataCorrupted(
          DecodingError.Context(
            codingPath: [],
            debugDescription: "Not a stored session in any known format."
          )
        )
      }
    }
  }
}
