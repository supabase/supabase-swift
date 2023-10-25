import Foundation

@_spi(Internal)
public final class LockIsolated<Value>: @unchecked Sendable {
  private var _value: Value
  private let lock = NSRecursiveLock()

  public init(_ value: @autoclosure @Sendable () throws -> Value) rethrows {
    self._value = try value()
  }

  public func withValue<T: Sendable>(
    _ operation: (inout Value) throws -> T
  ) rethrows -> T {
    try self.lock.sync {
      var value = self._value
      defer { self._value = value }
      return try operation(&value)
    }
  }

  public func setValue(_ newValue: @autoclosure @Sendable () throws -> Value) rethrows {
    try self.lock.sync {
      self._value = try newValue()
    }
  }
}

extension LockIsolated where Value: Sendable {
  /// The lock-isolated value.
  public var value: Value {
    self.lock.sync {
      self._value
    }
  }
}

extension LockIsolated: Equatable where Value: Equatable {
  public static func == (lhs: LockIsolated, rhs: LockIsolated) -> Bool {
    lhs.withValue { lhsValue in rhs.withValue { rhsValue in lhsValue == rhsValue } }
  }
}

extension LockIsolated: Hashable where Value: Hashable {
  public func hash(into hasher: inout Hasher) {
    self.withValue { hasher.combine($0) }
  }
}

extension NSRecursiveLock {
  @inlinable @discardableResult
  @_spi(Internal) public func sync<R>(work: () throws -> R) rethrows -> R {
    self.lock()
    defer { self.unlock() }
    return try work()
  }
}
