//
//  SupabaseError.swift
//  Helpers
//
//  Created by Guilherme Souza on 14/09/26.
//

public import Foundation

/// The root of every error the Supabase SDK throws.
///
/// `AuthError`, `PostgrestError`, `StorageError`, `FunctionsError` and `RealtimeError` all
/// conform. Catch the existential to handle failures from any module in one place:
///
/// ```swift
/// do {
///   try await supabase.from("todos").select().execute()
/// } catch let error as any SupabaseError {
///   logger.error("\(error.message) request=\(error.response?.requestID ?? "-")")
/// }
/// ```
///
/// Each conforming type has a `kind` property, a `RawRepresentable` struct with static
/// members, that says which failure it is. Compare against the known kinds and keep a
/// fallback branch; a newer server or SDK may add kinds.
///
/// Conforming to this protocol outside the Supabase SDK is not supported; the shared
/// `description` layout is internal to the package.
public protocol SupabaseError: Error, Sendable, LocalizedError, CustomStringConvertible {
  /// A human-readable description of what went wrong. Never empty.
  var message: String { get }

  /// The HTTP response that produced this error, when there was one.
  ///
  /// `nil` for failures that never reached the server (`transport`) and for client-side
  /// failures such as a missing session.
  var response: HTTPErrorResponse? { get }

  /// The error this one wraps.
  ///
  /// Set for `transport` kinds (usually a `URLError`) and `decoding` kinds (usually a
  /// `DecodingError`). `CancellationError` is never wrapped; it always propagates as itself.
  var underlyingError: (any Error)? { get }
}

extension SupabaseError {
  public var errorDescription: String? { message }
}

extension SupabaseError {
  /// Shared `description` layout for every module error:
  /// `TypeName(kind): message [status 404, request abc]`.
  package func formattedDescription(kind: String) -> String {
    var text = "\(String(describing: Self.self))(\(kind)): \(message)"
    if let response {
      text += " [status \(response.statusCode)"
      if let requestID = response.requestID {
        text += ", request \(requestID)"
      }
      text += "]"
    }
    return text
  }
}
