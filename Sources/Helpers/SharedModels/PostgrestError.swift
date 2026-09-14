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

    /// PostgREST rejected the request and sent an error body. See ``PostgrestError/serverError``.
    public static let server: Kind = "server"
    /// A non-2xx status whose body was not a PostgREST error payload, or a response the SDK
    /// could not interpret (for example a `count(_:)` reply with no `Content-Range`).
    /// ``PostgrestError/response`` has the raw body when there was one.
    public static let unexpectedResponse: Kind = "unexpectedResponse"
    /// The request never completed. ``PostgrestError/underlyingError`` is usually a `URLError`.
    public static let transport: Kind = "transport"
    /// A success body could not be decoded as the requested type.
    /// ``PostgrestError/underlyingError`` is usually a `DecodingError`.
    public static let decoding: Kind = "decoding"
    /// The SDK refused to send the request, e.g. RPC params that are not a JSON object for a
    /// `GET`, or two incompatible transforms on one query. No request was sent.
    public static let invalidRequest: Kind = "invalidRequest"
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
  }

  public var kind: Kind
  public var message: String
  /// The decoded error body. Non-nil exactly when ``kind`` is ``Kind-swift.struct/server``.
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
