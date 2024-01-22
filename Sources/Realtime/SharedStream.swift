//
//  SharedStream.swift
//
//
//  Created by Guilherme Souza on 12/01/24.
//

import ConcurrencyExtras
import Foundation

final class SharedStream<Element>: Sendable where Element: Sendable {
  private let storage = LockIsolated<[UUID: AsyncStream<Element>.Continuation]>([:])
  private let _value: LockIsolated<Element>

  var lastElement: Element { _value.value }

  init(initialElement: Element) {
    _value = LockIsolated(initialElement)
  }

  func makeStream() -> AsyncStream<Element> {
    let (stream, continuation) = AsyncStream<Element>.makeStream()
    let id = UUID()

    continuation.onTermination = { _ in
      self.storage.withValue {
        $0[id] = nil
      }
    }

    storage.withValue {
      $0[id] = continuation
    }

    continuation.yield(lastElement)

    return stream
  }

  func yield(_ value: Element) {
    _value.setValue(value)
    for continuation in storage.value.values {
      continuation.yield(value)
    }
  }

  func finish() {
    for continuation in storage.value.values {
      continuation.finish()
    }
  }
}
