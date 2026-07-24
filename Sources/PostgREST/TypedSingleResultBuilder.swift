//
//  TypedSingleResultBuilder.swift
//  PostgREST
//
//  Created by Guilherme Souza on 24/06/25.
//

import Foundation

/// Result of calling `single()` on a typed builder. `execute()` decodes a single `Selection`
/// value rather than an array.
public final class TypedSingleResultBuilder<Table, Selection>: PostgrestBuilder, @unchecked Sendable
{}

extension TypedSingleResultBuilder where Selection: SelectionRepresentable {
  @discardableResult
  public func execute(
    options: FetchOptions = FetchOptions()
  ) async throws -> PostgrestResponse<Selection> {
    try await execute(options: options) { [configuration] data in
      try configuration.decoder.decode(Selection.self, from: data)
    }
  }
}
