import Foundation

/// One argument of a `GET` or `HEAD` function call, decoded from the JSON its parameters encode
/// to, and rendered as the text of a query item.
///
/// It keeps a number's exact digits: `JSONValue` holds an `Int` or a `Double`, so a `UInt64`
/// above `Int.max` or a high-precision `Decimal` would be sent rounded, and PostgREST would run the
/// function on a different value with no error.
enum PostgrestArgument: Codable, Equatable {
  case null
  case bool(Bool)
  /// A number in its exact decimal digits.
  case number(Decimal)
  /// A number outside the range of `Decimal`, such as `1e300`.
  case double(Double)
  case string(String)
  case array([PostgrestArgument])
  case object([String: PostgrestArgument])

  private static let decoder = JSONDecoder()

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
  }()

  /// The arguments in `body`, one query item per key in key order, or `nil` when `body` is not a
  /// JSON object.
  static func queryItems(forJSONObject body: Data) -> [URLQueryItem]? {
    guard case .object(let arguments)? = try? decoder.decode(Self.self, from: body) else {
      return nil
    }
    return arguments.sorted { $0.key < $1.key }.map { key, value in
      URLQueryItem(name: key, value: value.queryValue)
    }
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let string = try? container.decode(String.self) {
      self = .string(string)
    } else if let bool = try? container.decode(Bool.self) {
      self = .bool(bool)
    } else if let number = try? container.decode(Decimal.self), !number.isNaN {
      self = .number(number)
    } else if let double = try? container.decode(Double.self) {
      self = .double(double)
    } else if let array = try? container.decode([PostgrestArgument].self) {
      self = .array(array)
    } else {
      self = .object(try container.decode([String: PostgrestArgument].self))
    }
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let bool): try container.encode(bool)
    case .number(let number): try container.encode(number)
    case .double(let double): try container.encode(double)
    case .string(let string): try container.encode(string)
    case .array(let array): try container.encode(array)
    case .object(let object): try container.encode(object)
    }
  }

  /// A Postgres array literal for an array, compact JSON with sorted keys for an object, and the
  /// plain text of any other value.
  var queryValue: String {
    switch self {
    case .null:
      return "null"
    case .bool(let bool):
      return bool ? "true" : "false"
    case .number(let number):
      return number.description
    case .double(let double):
      return String(double)
    case .string(let string):
      return string
    case .array(let array):
      return "{\(array.map(\.arrayElementValue).joined(separator: ","))}"
    case .object:
      guard let data = try? Self.encoder.encode(self) else { return "" }
      return String(decoding: data, as: UTF8.self)
    }
  }

  /// One element of a Postgres array literal. An element that is empty, spells NULL, or holds
  /// `,` `{` `}` `"` `\` is double-quoted, as for the `cs`/`cd` filters, so it stays one element
  /// with its own text. A nested array stays a bare sub-literal, and a JSON null a bare `null`.
  private var arrayElementValue: String {
    switch self {
    case .null, .array:
      return queryValue
    case .bool, .number, .double, .string, .object:
      return escapePostgRESTArrayLiteralElement(queryValue)
    }
  }
}
