//
//  AuthStateChangeListenerHandleTests.swift
//
//
//  Created by Guilherme Souza on 17/02/24.
//

@testable import Auth
import ConcurrencyExtras
import Foundation
import XCTest

final class AuthStateChangeListenerHandleTests: XCTestCase {
  func testRemove() {
    let handle = AuthStateChangeListenerHandle()

    let onRemoveCallCount = LockIsolated(0)
    handle._onRemove.setValue {
      onRemoveCallCount.withValue {
        $0 += 1
      }
    }

    handle.remove()
    handle.remove()

    XCTAssertEqual(onRemoveCallCount.value, 1)
  }

  func testDeinit() {
    var handle: AuthStateChangeListenerHandle? = AuthStateChangeListenerHandle()

    let onRemoveCallCount = LockIsolated(0)
    handle?._onRemove.setValue {
      onRemoveCallCount.withValue {
        $0 += 1
      }
    }

    handle = nil

    XCTAssertEqual(onRemoveCallCount.value, 1)
  }
}
