//
//  TaskLocalHelpers.swift
//
//
//  Created by Guilherme Souza on 29/05/24.
//

import Foundation

#if compiler(>=6.0)
  extension TaskLocal where Value == JSONObject {
    @discardableResult
    @inlinable package final func withValue<R>(
      merging valueDuringOperation: Value,
      operation: () async throws -> R,
      isolation: isolated (any Actor)? = #isolation,
      file: String = #fileID,
      line: UInt = #line
    ) async rethrows -> R {
      let currentValue = wrappedValue
      return try await withValue(
        currentValue.merging(valueDuringOperation) { _, new in new },
        operation: operation,
        isolation: isolation,
        file: file,
        line: line
      )
    }
  }
#else
  extension TaskLocal where Value == JSONObject {
    @_unsafeInheritExecutor
    @discardableResult
    @inlinable package final func withValue<R>(
      merging valueDuringOperation: Value,
      operation: () async throws -> R,
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
#endif
