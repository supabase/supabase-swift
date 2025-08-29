//
//  WrappingError.swift
//  Supabase
//
//  Created by Guilherme Souza on 28/08/25.
//


/// Wraps an error in an ``AuthError`` if it's not already one.
package func wrappingError<R: Sendable, E: Error>(
  or mapError: (any Error) -> E,
  _ block: () throws -> R
) throws(E) -> R {
  do {
    return try block()
  } catch {
    throw mapError(error)
  }
}

/// Wraps an error in an ``AuthError`` if it's not already one.
package func wrappingError<R: Sendable, E: Error>(
  or mapError: (any Error) -> E,
  @_inheritActorContext _ block: @escaping @Sendable () async throws -> R
) async throws(E) -> R {
  do {
    return try await block()
  } catch {
    throw mapError(error)
  }
}
