//
//  ObservationTokenTests.swift
//
//
//  Created by Guilherme Souza on 17/02/24.
//

import ConcurrencyExtras
import Foundation
import Helpers
import XCTest

final class ObservationTokenTests: XCTestCase {
  func testRemove() {
    let handle = ObservationToken()

    let onRemoveCallCount = LockIsolated(0)
    handle.onCancel = {
      onRemoveCallCount.withValue {
        $0 += 1
      }
    }

    handle.cancel()
    handle.cancel()

    XCTAssertEqual(onRemoveCallCount.value, 1)
  }

  func testDeinit() {
    var handle: ObservationToken? = ObservationToken()

    let onRemoveCallCount = LockIsolated(0)
    handle?.onCancel = {
      onRemoveCallCount.withValue {
        $0 += 1
      }
    }

    handle = nil

    XCTAssertEqual(onRemoveCallCount.value, 1)
  }
}
