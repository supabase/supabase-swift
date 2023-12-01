//
//  TimeoutTimerTests.swift
//
//
//  Created by Guilherme Souza on 30/11/23.
//

import ConcurrencyExtras
@testable import Realtime
import XCTest

final class TimeoutTimerTests: XCTestCase {
  func testTimeoutTimer() async throws {
    let timer = TimeoutTimer()

    let handlerCallCount = LockIsolated(0)
    timer.setHandler {
      handlerCallCount.withValue { $0 += 1 }
    }

    let timeCalculationParams = LockIsolated([Int]())
    timer.setTimerCalculation { tries in
      timeCalculationParams.withValue {
        $0.append(tries)
      }
      return 1
    }

    timer.scheduleTimeout()

    try await Task.sleep(nanoseconds: NSEC_PER_SEC * 2)

    XCTAssertEqual(handlerCallCount.value, 1)

    timer.scheduleTimeout()
    try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 500)

    XCTAssertEqual(handlerCallCount.value, 1)
  }
}
