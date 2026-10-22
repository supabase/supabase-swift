//
//  PostgrestError.swift
//
//
//  Created by Guilherme Souza on 27/01/24.
//

import Foundation

/// An error thrown by the PostgREST client.
///
/// Check ``kind`` to learn what failed. For ``Kind-swift.struct/server``, ``serverError`` holds
/// the body PostgREST returned (`code`, `message`, `details`, `hint`) and ``response`` holds the
/// status, headers and request id.
///
/// ```swift
/// do {
///   try await supabase.from("todos").insert(todo).execute()
/// } catch let error as PostgrestError where error.serverError?.code == "23505" {
///   showDuplicate(error.serverError?.details)
/// }
/// ```
public struct PostgrestError: SupabaseError {
  /// What failed. Compare against the static members and keep a fallback branch.
  public struct Kind: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
      self.init(rawValue: value)
    }

    /// PostgREST answered with a non-2xx status. Branch on ``PostgrestError/response`` for the
    /// status code and on ``PostgrestError/serverError`` for the PostgreSQL or PostgREST error
    /// code; `serverError` is `nil` when the body was not a PostgREST error payload.
    public static let server: Kind = "server"
    /// No response arrived, so whether the database applied the request is unknown. Retry reads
    /// freely; before retrying a write, check that it was not applied.
    /// ``PostgrestError/underlyingError`` is usually a `URLError`.
    public static let transport: Kind = "transport"
    /// PostgREST answered 2xx but the body could not be used: the rows did not decode as the
    /// requested type, or a `count(_:)` reply had no `Content-Range`. Nothing to retry; fix the
    /// model or report it. ``PostgrestError/underlyingError`` is the `DecodingError` when there
    /// was one.
    public static let decoding: Kind = "decoding"
    /// The SDK refused to send the request, e.g. RPC params that are not a JSON object for a
    /// `GET`, or two incompatible transforms on one query. Fix the call. No request was sent.
    public static let invalidRequest: Kind = "invalidRequest"
    /// The access-token provider (`PostgrestClient.Configuration.accessToken`) threw, so the
    /// request could not be authenticated and was not sent. ``PostgrestError/underlyingError`` is
    /// the provider's error, for example an Auth refresh failure.
    public static let accessToken: Kind = "accessToken"
  }

  /// The error body PostgREST returns for a rejected request, with its wire field names.
  public struct ServerError: Decodable, Hashable, Sendable {
    /// The PostgREST or PostgreSQL error code, e.g. `"PGRST116"` or `"23505"`.
    public var code: String?
    /// The human-readable message.
    public var message: String
    /// Additional detail, as returned by PostgREST in the `details` field.
    public var details: String?
    /// A hint on how to fix the problem, when PostgREST sends one.
    public var hint: String?

    public init(code: String? = nil, message: String, details: String? = nil, hint: String? = nil) {
      self.code = code
      self.message = message
      self.details = details
      self.hint = hint
    }

    private enum CodingKeys: String, CodingKey {
      case code, message, details, hint
    }

    public init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      code = try container.decodeIfPresent(String.self, forKey: .code)
      message = try container.decode(String.self, forKey: .message)
      hint = try container.decodeIfPresent(String.self, forKey: .hint)
      switch try container.decodeIfPresent(JSONValue.self, forKey: .details) {
      case nil, .null:
        details = nil
      case .string(let text):
        details = text
      case let structured?:
        // Not always a string: an ambiguous embed (`PGRST201`) sends an array of candidate
        // relationships. Kept as JSON text so the field stays a `String` and nothing is dropped.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        details = String(decoding: try encoder.encode(structured), as: UTF8.self)
      }
    }
  }

  public var kind: Kind
  public var message: String
  /// The decoded error body. Set when ``kind`` is ``Kind-swift.struct/server`` and the body was
  /// a PostgREST error payload; `nil` otherwise.
  public var serverError: ServerError?
  public var response: HTTPErrorResponse?
  public var underlyingError: (any Error)?

  public init(
    kind: Kind,
    message: String,
    serverError: ServerError? = nil,
    response: HTTPErrorResponse? = nil,
    underlyingError: (any Error)? = nil
  ) {
    self.kind = kind
    self.message = message
    self.serverError = serverError
    self.response = response
    self.underlyingError = underlyingError
  }

  public var description: String {
    formattedDescription(kind: kind.rawValue)
  }
}

extension PostgrestError.ServerError {
  /// Whether a `PGRST116` error was caused by the query matching zero rows, as opposed to more
  /// than one row.
  ///
  /// PostgREST reports both cases with the same error code; the row count is only distinguishable
  /// via the `details` message. The exact wording has varied across PostgREST versions, e.g.
  /// "Results contain 0 rows, application/vnd.pgrst.object+json requires 1 row" and "The result
  /// contains 0 rows". Both mention the matched row count immediately before a "row"/"rows" word,
  /// so look for that instead of matching a fixed prefix.
  package var matchedZeroRows: Bool {
    guard let details else { return false }
    let words = details.split(separator: " ")
    guard let rowsIndex = words.firstIndex(where: { $0.hasPrefix("row") }), rowsIndex > 0,
      let count = Int(words[rowsIndex - 1])
    else { return false }
    return count == 0
  }
}
