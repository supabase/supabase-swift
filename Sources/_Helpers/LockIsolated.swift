//
//  File.swift
//
//
//  Created by Guilherme Souza on 07/10/23.
//

import Foundation

@_spi(Internal)
public final class LockIsolated<Value>: @unchecked Sendable {
  private let lock = NSRecursiveLock()
  private var _value: Value

  public init(_ value: Value) {
    self._value = value
  }

  @discardableResult
  public func withValue<T>(_ block: (inout Value) throws -> T) rethrows -> T {
    try lock.sync {
      var value = self._value
      defer { self._value = value }
      return try block(&value)
    }
  }

  public var value: Value {
    lock.sync { self._value }
  }
}

extension NSRecursiveLock {
  @discardableResult
  func sync<R>(work: () throws -> R) rethrows -> R {
    lock()
    defer { unlock() }
    return try work()
  }
}
