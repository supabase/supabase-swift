//
//  TaskLocalHelpers.swift
//
//
//  Created by Guilherme Souza on 29/05/24.
//

import Foundation

extension TaskLocal where Value == JSONObject {
  @inlinable
  @discardableResult
  @_unsafeInheritExecutor
  package func withValue<R>(
    merging valueDuringOperation: Value,
    @_inheritActorContext operation: @Sendable () async throws -> R,
    file: String = #fileID,
    line: UInt = #line
  ) async rethrows -> R {
    let currentValue = wrappedValue
    return try await withValue(
      currentValue.merging(valueDuringOperation) { _, new in new },
      operation: operation,
      file: file,
      line: line
    )
  }
}
