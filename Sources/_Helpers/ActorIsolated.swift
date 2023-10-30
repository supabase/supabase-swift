//
//  ActorIsolated.swift
//
//
//  Created by Guilherme Souza on 07/10/23.
//

import Foundation

@_spi(Internal)
public final class ActorIsolated<Value> {
  public var value: Value

  public init(_ value: @autoclosure @Sendable () throws -> Value) rethrows {
    self.value = try value()
  }

  @discardableResult
  public func withValue<T>(_ block: @Sendable (inout Value) throws -> T) rethrows -> T {
    var value = value
    defer { self.value = value }
    return try block(&value)
  }

  public func setValue(_ newValue: @autoclosure @Sendable () throws -> Value) rethrows {
    value = try newValue()
  }
}
