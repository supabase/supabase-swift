//
//  PostgrestTypedQuery.swift
//  PostgREST
//
//  Created by Guilherme Souza on 21/08/26.
//

/// A read request against a relation, with filters and modifiers applied by key path.
///
/// `Phase` mirrors the phase parameter on ``PostgrestRequestBuilder``: it is a compile-time-only
/// marker that decides which methods are available. Filters need a
/// ``PostgrestFilterablePhase``, `order`/`limit` need a ``PostgrestTransformablePhase``, and
/// ``execute()`` needs a ``PostgrestExecutablePhase``. You never spell it out — it is inferred
/// from the chain.
///
/// Like the builder it wraps, this is a value type: chaining off the same query twice gives two
/// independent requests.
public struct PostgrestTypedQuery<
  R: PostgrestRelation,
  Output: Decodable & Sendable,
  Phase
>: Sendable {
  /// The underlying string-based builder.
  public let builder: PostgrestRequestBuilder<Phase>

  /// Wraps a builder in the typed query surface.
  ///
  /// - Parameter builder: The builder to wrap.
  public init(builder: PostgrestRequestBuilder<Phase>) {
    self.builder = builder
  }
}

extension PostgrestTypedQuery where Phase: PostgrestExecutablePhase {
  /// Sends the request and decodes the response.
  ///
  /// - Returns: A ``PostgrestResponse`` whose `value` is the decoded `Output`.
  @discardableResult
  public func execute() async throws -> PostgrestResponse<Output> {
    try await builder.execute()
  }
}
