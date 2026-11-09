//
//  PostgrestError.swift
//
//
//  Created by Guilherme Souza on 27/01/24.
//

import Foundation
import HTTPTypes

/// An error thrown by the PostgREST client.
///
/// Check ``kind`` to learn what failed. For ``Kind-swift.struct/server``, ``code`` holds the
/// PostgreSQL or PostgREST error code, ``serverError`` holds the rest of the body PostgREST
/// returned (`message`, `details`, `hint`), and ``response`` holds the status, headers and
/// request id.
///
/// ```swift
/// do {
///   try await supabase.from("todos").insert(todo).execute()
/// } catch PostgrestError.Code.uniqueViolation {
///   showDuplicate()
/// } catch let error as PostgrestError where error.code == .foreignKeyViolation {
///   showMissingParent(error.serverError?.details)
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

    /// PostgREST answered with a non-2xx status. Branch on ``PostgrestError/code`` for the
    /// PostgreSQL or PostgREST error code and on ``PostgrestError/response`` for the status
    /// code; ``PostgrestError/serverError`` is `nil` when the body was not a PostgREST error
    /// payload.
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

  /// A PostgreSQL `SQLSTATE` or a PostgREST `PGRST` code, as PostgREST sends it in the `code`
  /// field of an error body.
  ///
  /// The static members name common PostgreSQL codes. Any other code, such as `"PGRST116"`,
  /// round-trips through ``rawValue``, so compare with a string literal and keep a fallback
  /// branch. The full lists are the PostgreSQL "Error Codes" appendix and the PostgREST "Errors"
  /// reference.
  public struct Code: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    /// The code as PostgREST sends it, such as `"23505"`.
    public let rawValue: String

    /// Creates a code from the value PostgREST sends.
    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    /// Creates a code from a string literal.
    public init(stringLiteral value: String) {
      self.init(rawValue: value)
    }

    /// `23505`: a row with the same value in a unique column or primary key already exists.
    public static let uniqueViolation: Code = "23505"
    /// `23503`: the row references a row that does not exist, or is still referenced.
    public static let foreignKeyViolation: Code = "23503"
    /// `23502`: a `NOT NULL` column got `NULL`.
    public static let notNullViolation: Code = "23502"
    /// `23514`: a `CHECK` constraint rejected the row.
    public static let checkViolation: Code = "23514"
    /// `22P02`: a value is not valid input for its column type, such as text for a `uuid`.
    public static let invalidTextRepresentation: Code = "22P02"
    /// `42501`: the role lacks a privilege, or a row level security policy rejected the row.
    public static let insufficientPrivilege: Code = "42501"
    /// `42P01`: the table or view does not exist.
    public static let undefinedTable: Code = "42P01"
    /// `42703`: the column does not exist.
    public static let undefinedColumn: Code = "42703"
    /// `42883`: no function matches the name and argument types.
    public static let undefinedFunction: Code = "42883"
    /// `40001`: a serializable transaction could not complete. Retry it.
    public static let serializationFailure: Code = "40001"
    /// `40P01`: the transaction was chosen as a deadlock victim. Retry it.
    public static let deadlockDetected: Code = "40P01"
    /// `57014`: the statement was canceled, for example by `statement_timeout`.
    public static let queryCanceled: Code = "57014"
    /// `P0001`: a PL/pgSQL `RAISE EXCEPTION` without its own `ERRCODE`.
    public static let raiseException: Code = "P0001"
  }

  /// The error body PostgREST returns for a rejected request, without its code, which is
  /// ``PostgrestError/code``.
  public struct ServerError: Hashable, Sendable {
    /// The human-readable message.
    public var message: String
    /// Additional detail, as returned by PostgREST in the `details` field.
    public var details: String?
    /// A hint on how to fix the problem, when PostgREST sends one.
    public var hint: String?

    public init(message: String, details: String? = nil, hint: String? = nil) {
      self.message = message
      self.details = details
      self.hint = hint
    }
  }

  public var kind: Kind
  public var message: String
  /// The PostgreSQL or PostgREST error code, such as ``Code-swift.struct/uniqueViolation`` or
  /// `"PGRST116"`. `nil` when the server sent none.
  public var code: Code?
  /// The decoded error body. Set when ``kind`` is ``Kind-swift.struct/server`` and the body was
  /// a PostgREST error payload; `nil` otherwise.
  public var serverError: ServerError?
  public var response: HTTPErrorResponse?
  public var underlyingError: (any Error)?

  public init(
    kind: Kind,
    message: String,
    code: Code? = nil,
    serverError: ServerError? = nil,
    response: HTTPErrorResponse? = nil,
    underlyingError: (any Error)? = nil
  ) {
    self.kind = kind
    self.message = message
    self.code = code
    self.serverError = serverError
    self.response = response
    self.underlyingError = underlyingError
  }

  public var description: String {
    formattedDescription(kind: kind.rawValue)
  }
}

extension PostgrestError.Kind {
  /// Matches a ``PostgrestError`` of this ``PostgrestError/kind``, so a `catch` clause can name
  /// the kind directly.
  ///
  /// ```swift
  /// do {
  ///   try await supabase.from("todos").select().execute()
  /// } catch PostgrestError.Kind.transport {
  ///   showOfflineBanner()
  /// }
  /// ```
  public static func ~= (kind: PostgrestError.Kind, error: any Error) -> Bool {
    (error as? PostgrestError)?.kind == kind
  }
}

extension PostgrestError.Code {
  /// Matches a ``PostgrestError`` with this ``PostgrestError/code``, so a `catch` clause can name
  /// the code directly.
  ///
  /// ```swift
  /// do {
  ///   try await supabase.from("todos").insert(todo).execute()
  /// } catch PostgrestError.Code.uniqueViolation {
  ///   showDuplicate()
  /// }
  /// ```
  public static func ~= (code: PostgrestError.Code, error: any Error) -> Bool {
    (error as? PostgrestError)?.code == code
  }
}

extension PostgrestError {
  /// The error for a non-2xx response: the decoded body when it is a PostgREST error payload, or
  /// the status alone.
  static func server(_ response: HTTPResponse, body: Data) -> PostgrestError {
    let errorResponse = HTTPErrorResponse(response, body: body)
    guard let decoded = try? JSONDecoder().decode(Body.self, from: body) else {
      return PostgrestError(
        kind: .server,
        message: "Unexpected response with status code \(response.status.code).",
        response: errorResponse
      )
    }
    return PostgrestError(
      kind: .server,
      message: decoded.serverError.message,
      code: decoded.code,
      serverError: decoded.serverError,
      response: errorResponse
    )
  }

  /// A decoded PostgREST error body: the code goes to ``PostgrestError/code`` and the rest to
  /// ``PostgrestError/ServerError``.
  struct Body: Decodable {
    var code: Code?
    var serverError: ServerError

    private enum CodingKeys: String, CodingKey {
      case code, message, details, hint
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      code = try container.decodeIfPresent(String.self, forKey: .code).map(Code.init(rawValue:))
      let details: String?
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
      serverError = ServerError(
        message: try container.decode(String.self, forKey: .message),
        details: details,
        hint: try container.decodeIfPresent(String.self, forKey: .hint))
    }
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
  var matchedZeroRows: Bool {
    guard let details else { return false }
    let words = details.split(separator: " ")
    guard let rowsIndex = words.firstIndex(where: { $0.hasPrefix("row") }), rowsIndex > 0,
      let count = Int(words[rowsIndex - 1])
    else { return false }
    return count == 0
  }
}
