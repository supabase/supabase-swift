//
//  WeakBox.swift
//
//
//  Created by Guilherme Souza on 29/11/23.
//

import Foundation

final class WeakBox<Value: AnyObject>: @unchecked Sendable {
  private let lock = NSRecursiveLock()
  private weak var _value: Value?

  var value: Value? {
    lock.withLock {
      _value
    }
  }

  func setValue(_ value: Value?) {
    lock.withLock {
      _value = value
    }
  }

  init(_ value: Value? = nil) {
    _value = value
  }
}
