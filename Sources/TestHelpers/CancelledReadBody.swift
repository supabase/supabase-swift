//
//  CancelledReadBody.swift
//  TestHelpers
//
//  Created by Guilherme Souza on 09/11/26.
//

package import Foundation
package import Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

extension HTTPBody {
  /// A response body that yields `prefix`, calls `reading`, then waits until the reading task is
  /// cancelled and throws `URLError(.cancelled)`, the way `URLSession` reports a cancel during a
  /// body read.
  package static func cancelledRead(
    prefix: Data = Data("{".utf8),
    reading: @escaping @Sendable () -> Void
  ) -> HTTPBody {
    HTTPBody(
      CancelledReadSequence(prefix: prefix, reading: reading), length: .unknown,
      iterationBehavior: .single)
  }
}

private struct CancelledReadSequence: AsyncSequence, Sendable {
  typealias Element = ArraySlice<UInt8>

  let prefix: Data
  let reading: @Sendable () -> Void

  struct AsyncIterator: AsyncIteratorProtocol {
    let prefix: Data
    let reading: @Sendable () -> Void
    var yieldedPrefix = false

    mutating func next() async throws -> ArraySlice<UInt8>? {
      if !yieldedPrefix {
        yieldedPrefix = true
        return ArraySlice(prefix)
      }
      reading()
      try? await Task.sleep(for: .seconds(3600))
      throw URLError(.cancelled)
    }
  }

  func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(prefix: prefix, reading: reading)
  }
}
