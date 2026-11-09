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
    var session: Session
    /// `false` when the data is a v2 shape that the caller should rewrite as schema 1.
    var isCurrentSchema: Bool
  }

  /// A session that a newer SDK wrote. It is not corrupt, so the caller must keep it: an older
  /// SDK reads it after a downgrade, or in an app extension on another SDK version.
  struct NewerSchema: Error, Equatable {
    var schema: Int
  }

  /// - Throws: ``NewerSchema`` for a schema above ``PersistedSession/currentSchema``, and
  ///   `DecodingError` for data that no SDK version wrote.
  static func decode(_ data: Data) throws -> Decoded {
    switch try JSONDecoder().decode(Shape.self, from: data) {
    case .schema(PersistedSession.currentSchema):
      let persisted = try PersistedJSON.decoder.decode(PersistedSession.self, from: data)
      return Decoded(session: try persisted.session(), isCurrentSchema: true)

    case .schema(let schema) where schema > PersistedSession.currentSchema:
      throw NewerSchema(schema: schema)

    case .schema(let schema):
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: [PersistedSession.CodingKeys.schema],
          debugDescription: "Unsupported stored session schema \(schema)."
        )
      )

    case .v2Wrapped:
      let wrapped = try v2SnakeCaseDecoder.decode(V2WrappedSession.self, from: data)
      return Decoded(session: wrapped.session, isCurrentSchema: false)

    case .v2SnakeCase:
      let session = try v2SnakeCaseDecoder.decode(Session.self, from: data)
      return Decoded(session: session, isCurrentSchema: false)

    case .v2CamelCase:
      let session = try v2CamelCaseDecoder.decode(Session.self, from: data)
      return Decoded(session: session, isCurrentSchema: false)
    }
  }

  static func encode(_ session: Session) throws -> Data {
    try PersistedJSON.encoder.encode(PersistedSession(session))
  }

  /// Reads the v2 snake_case shapes. `Session` now declares snake_case keys, so only the
  /// free-form metadata objects need their keys restored to the camelCase that v2 decoded them to.
  private static let v2SnakeCaseDecoder: JSONDecoder = {
    let decoder = JSONDecoder.supabase()
    decoder.keyDecodingStrategy = .custom { path in
      let key = path[path.count - 1]
      return isFreeFormObject(path) ? LegacyKey(camelCased(key.stringValue)) : key
    }
    return decoder
  }()

  /// Reads the v2 camelCase shape. It maps each key that v2 wrote to the snake_case key that
  /// `Session` declares now, and leaves the keys of free-form metadata objects as stored.
  private static let v2CamelCaseDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .custom { path in
      let key = path[path.count - 1]
      return isFreeFormObject(path) ? key : LegacyKey(snakeCased(key.stringValue))
    }
    return decoder
  }()

  private struct LegacyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(_ stringValue: String) { self.stringValue = stringValue }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
  }

  private static let freeFormObjects: Set<String> = [
    "userMetadata", "user_metadata", "appMetadata", "app_metadata", "identityData",
    "identity_data",
  ]

  /// Whether `path` points inside a user-supplied JSON object, whose keys are data.
  private static func isFreeFormObject(_ path: [any CodingKey]) -> Bool {
    path.dropLast().contains { freeFormObjects.contains($0.stringValue) }
  }

  private static func snakeCased(_ key: String) -> String {
    var result = ""
    for (index, character) in key.enumerated() {
      if character.isUppercase, index > 0 { result.append("_") }
      result.append(contentsOf: character.lowercased())
    }
    return result
  }

  /// Foundation's `convertFromSnakeCase` for one key: leading and trailing underscores stay.
  private static func camelCased(_ key: String) -> String {
    let leading = key.prefix { $0 == "_" }
    let trailing = key.dropFirst(leading.count).reversed().prefix { $0 == "_" }
    let core = key.dropFirst(leading.count).dropLast(trailing.count)
    let words = core.split(separator: "_", omittingEmptySubsequences: true)
    guard let first = words.first else { return key }
    let rest = words.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }
    return leading + first + rest.joined() + trailing
  }

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
