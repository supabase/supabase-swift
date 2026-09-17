//
//  TaskLocalHelpers.swift
//
//
//  Created by Guilherme Souza on 29/05/24.
//

import Foundation

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
