//
//  StreamManager.swift
//
//
//  Created by Guilherme Souza on 12/01/24.
//

import ConcurrencyExtras
import Foundation

public final class AsyncStreamManager<Element> {
  private let storage = LockIsolated<[UUID: AsyncStream<Element>.Continuation]>([:])
  private let _value = LockIsolated<Element?>(nil)

  public var value: Element? { _value.value }

  public init() {}

  public func makeStream() -> AsyncStream<Element> {
    let (stream, continuation) = AsyncStream<Element>.makeStream()
    let id = UUID()

    continuation.onTermination = { [weak self] _ in
      self?.storage.withValue {
        $0[id] = nil
      }
    }

    storage.withValue {
      $0[id] = continuation
    }

    return stream
  }

  public func yield(_ value: Element) {
    _value.setValue(value)
    for continuation in storage.value.values {
      continuation.yield(value)
    }
  }
}
