//
//  ObservationTokenTests.swift
//
//
//  Created by Guilherme Souza on 17/02/24.
//

import ConcurrencyExtras
import Foundation
import Helpers
import Testing

@Suite
struct ObservationTokenTests {
  @Test
  func remove() {
    let onRemoveCallCount = LockIsolated(0)
    let handle = ObservationToken {
      onRemoveCallCount.withValue {
        $0 += 1
      }
    }

    handle.cancel()
    handle.cancel()

    #expect(onRemoveCallCount.value == 1)
  }

  @Test
  func deinitCancelsToken() {
    let onRemoveCallCount = LockIsolated(0)
    var handle: ObservationToken? = ObservationToken {
      onRemoveCallCount.withValue {
        $0 += 1
      }
    }

    _ = handle  // Silence unused variable warning
    handle = nil

    #expect(onRemoveCallCount.value == 1)
  }
}
