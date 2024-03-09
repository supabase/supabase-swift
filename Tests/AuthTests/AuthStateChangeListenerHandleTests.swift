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
@testable import _Helpers

final class AuthStateChangeListenerHandleTests: XCTestCase {
  func testRemove() {
    let handle = ObservationToken()

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
    var handle: ObservationToken? = ObservationToken()

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
