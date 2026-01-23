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
    let onRemoveCallCount = LockIsolated(0)
    let handle = ObservationToken {
      onRemoveCallCount.withValue {
        $0 += 1
      }
    }

    handle.cancel()
    handle.cancel()

    XCTAssertEqual(onRemoveCallCount.value, 1)
  }

  func testDeinit() {
    let onRemoveCallCount = LockIsolated(0)
    var handle: ObservationToken? = ObservationToken {
      onRemoveCallCount.withValue {
        $0 += 1
      }
    }

    _ = handle  // Silence unused variable warning
    handle = nil

    XCTAssertEqual(onRemoveCallCount.value, 1)
  }
}
