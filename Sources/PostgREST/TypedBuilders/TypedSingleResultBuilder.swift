//
//  TypedSingleResultBuilder.swift
//  PostgREST
//
//  Created by Guilherme Souza on 24/06/25.
//

import Foundation
import SupabaseSwiftMacros

/// Wraps a PostgrestTransformBuilder after .single() has been called.
/// execute() returns a single decoded value rather than an array.
public struct TypedSingleResultBuilder<
  Table: ReadOnlyTableRepresentable,
  Selection: SelectionRepresentable
>: Sendable {
  let underlying: PostgrestTransformBuilder

  public func execute() async throws -> PostgrestResponse<Selection> {
    try await underlying.execute()
  }
}
