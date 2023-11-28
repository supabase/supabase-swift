//
//  ArrayExtensions.swift
//
//
//  Created by Guilherme Souza on 28/11/23.
//

import Foundation

extension Array {
  @_disfavoredOverload
  @inlinable func filter(_ isIncluded: (Element) async throws -> Bool) async rethrows -> [Element] {
    var result: [Element] = []
    for element in self {
      if try await isIncluded(element) {
        result.append(element)
      }
    }
    return result
  }

  @inlinable func first(where predicate: (Element) async throws -> Bool) async rethrows
    -> Element?
  {
    for element in self {
      if try await predicate(element) {
        return element
      }
    }
    return nil
  }
}
