//
//  PostgrestError.swift
//
//
//  Created by Guilherme Souza on 27/01/24.
//

public import Foundation

/// An error returned by PostgREST, or created by the PostgREST client before it sends a request.
///
/// ``code`` holds the PostgreSQL or PostgREST error code. ``serverError`` holds the rest of the
/// body (`message`, `details`, `hint`). Use a ``Code-swift.struct`` as a `catch` pattern:
///
/// ```swift
/// do {
///   try await supabase.from("todos").insert(todo).execute()
/// } catch PostgrestError.Code.uniqueViolation {
///   showDuplicate()
/// }
/// ```
public struct PostgrestError: Error, Codable, Sendable {
  private let storedDetails: String?
  private let storedHint: String?

  /// Additional detail about the error, as returned by PostgREST in the `details` field.
  @available(*, deprecated, message: "Use serverError?.details instead.")
  public var details: String? { storedDetails }

  /// A hint on how to fix the problem, when PostgREST sends one.
  @available(*, deprecated, message: "Use serverError?.hint instead.")
  public var hint: String? { storedHint }

  /// The PostgreSQL or PostgREST error code, such as `"23505"` or `"PGRST116"`. `nil` when the
  /// server sent none. ``Code-swift.struct`` names the common codes.
  public let code: String?
  public let message: String

  @available(*, deprecated, message: "Use serverError?.details instead.")
  public var detail: String? { storedDetails }

  private enum CodingKeys: String, CodingKey {
    case storedDetails = "details"
    case storedHint = "hint"
    case code
    case message
  }

  public init(
    details: String? = nil,
    hint: String? = nil,
    code: String? = nil,
    message: String
  ) {
    self.storedHint = hint
    self.storedDetails = details
    self.code = code
    self.message = message
  }

  @available(*, deprecated, renamed: "init(details:hint:code:message:)")
  public init(
    detail: String?,
    hint: String? = nil,
    code: String? = nil,
    message: String
  ) {
    self.init(details: detail, hint: hint, code: code, message: message)
  }
}

extension PostgrestError: LocalizedError {
  public var errorDescription: String? {
    message
  }
}

extension PostgrestError {
  /// A PostgreSQL `SQLSTATE` or a PostgREST `PGRST` code, as PostgREST sends it in the `code`
  /// field of an error body.
  ///
  /// The static members name common PostgreSQL codes. Any other code, such as `"PGRST116"`,
  /// round-trips through ``rawValue``, so compare with a string literal and keep a fallback
  /// branch. The full lists are the PostgreSQL "Error Codes" appendix and the PostgREST "Errors"
  /// reference.
  ///
  /// Use a code as a `catch` pattern:
  ///
  /// ```swift
  /// do {
  ///   try await supabase.from("todos").insert(todo).execute()
  /// } catch PostgrestError.Code.uniqueViolation {
  ///   showDuplicate()
  /// }
  /// ```
  ///
  /// > Note: In this version ``PostgrestError/code`` is still a `String?`, and the next major
  /// > version changes it to `Code?`. To write code that compiles on both versions, use the
  /// > `catch` pattern above, `PostgrestError.Code.uniqueViolation ~= error`, or compare with a
  /// > string literal (`error.code == "23505"`).
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

    /// Creates a server error body.
    ///
    /// - Parameters:
    ///   - message: The human-readable message.
    ///   - details: Additional detail about the error.
    ///   - hint: A hint on how to fix the problem.
    public init(message: String, details: String? = nil, hint: String? = nil) {
      self.message = message
      self.details = details
      self.hint = hint
    }
  }

  /// The error body, as ``ServerError``: ``message``, ``details`` and ``hint``.
  ///
  /// > Note: In this version the value is never `nil`. The error does not record where it came
  /// > from, so an error that the SDK creates before it sends a request also returns a value,
  /// > with only the message set. The next major version returns `nil` for an error that did not
  /// > come from a PostgREST error body.
  public var serverError: ServerError? {
    ServerError(message: message, details: storedDetails, hint: storedHint)
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
  // Without this, the operator wins every string-literal pattern whose subject is an `Error` that
  // a string literal can express, and such a pattern on an app's own type stops matching.
  @_disfavoredOverload
  public static func ~= (code: PostgrestError.Code, error: any Error) -> Bool {
    (error as? PostgrestError)?.code == code.rawValue
  }
}
