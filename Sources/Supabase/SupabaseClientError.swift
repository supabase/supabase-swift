//
//  SupabaseClientError.swift
//  Supabase
//
//  Created by Guilherme Souza on 06/11/26.
//

import Foundation
public import Helpers

/// An error thrown when a ``SupabaseClient`` cannot be created.
///
/// ```swift
/// do {
///   let supabase = try SupabaseClient(supabaseURL: tenant.url, supabaseKey: tenant.key)
/// } catch let error as SupabaseClientError where error.kind == .invalidConfiguration {
///   logger.error("tenant \(tenant.id) is misconfigured: \(error.message)")
/// }
/// ```
public struct SupabaseClientError: SupabaseError {
  /// What failed. Compare against the static members and keep a fallback branch.
  public struct Kind: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    /// The kind's name, e.g. `"invalidConfiguration"`.
    public let rawValue: String

    /// Creates a kind from its name.
    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    /// Creates a kind from a string literal.
    public init(stringLiteral value: String) {
      self.init(rawValue: value)
    }

    /// The `supabaseURL` passed to ``SupabaseClient/init(supabaseURL:supabaseKey:options:)`` has
    /// no scheme or no host. Fix the URL. No client was created.
    public static let invalidConfiguration: Kind = "invalidConfiguration"
  }

  /// What failed.
  public var kind: Kind

  /// A human-readable description of what went wrong.
  public var message: String

  /// Always `nil`: the client fails before it sends a request.
  public var response: HTTPErrorResponse? { nil }

  /// Always `nil`.
  public var underlyingError: (any Error)? { nil }

  /// Creates an error.
  ///
  /// - Parameters:
  ///   - kind: What failed.
  ///   - message: A human-readable description of what went wrong.
  public init(kind: Kind, message: String) {
    self.kind = kind
    self.message = message
  }

  public var description: String {
    formattedDescription(kind: kind.rawValue)
  }
}
