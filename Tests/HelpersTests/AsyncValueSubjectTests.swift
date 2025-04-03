//
//  AsyncValueSubjectTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 24/03/25.
//

import ConcurrencyExtras
import XCTest

@testable import Helpers

final class AsyncValueSubjectTests: XCTestCase {

  func testInitialValue() async {
    let subject = AsyncValueSubject<Int>(42)
    XCTAssertEqual(subject.value, 42)
  }

  func testYieldUpdatesValue() async {
    let subject = AsyncValueSubject<Int>(0)
    subject.yield(10)
    XCTAssertEqual(subject.value, 10)
  }

  func testValuesStream() async {
    let subject = AsyncValueSubject<Int>(0)
    let values = LockIsolated<[Int]>([])

    let task = Task {
      for await value in subject.values {
        let values = values.withValue {
          $0.append(value)
          return $0
        }
        if values.count == 4 {
          break
        }
      }
    }

    await Task.megaYield()

    subject.yield(1)
    subject.yield(2)
    subject.yield(3)
    subject.finish()

    await task.value

    XCTAssertEqual(values.value, [0, 1, 2, 3])
  }

  func testOnChangeHandler() async {
    let subject = AsyncValueSubject<Int>(0)
    let values = LockIsolated<[Int]>([])

    let task = subject.onChange { value in
      values.withValue {
        $0.append(value)
      }
    }

    await Task.megaYield()

    subject.yield(1)
    subject.yield(2)
    subject.yield(3)
    subject.finish()

    await task.value

    XCTAssertEqual(values.value, [0, 1, 2, 3])
  }

  func testFinish() async {
    let subject = AsyncValueSubject<Int>(0)
    let values = LockIsolated<[Int]>([])

    let task = Task {
      for await value in subject.values {
        values.withValue { $0.append(value) }
      }
    }

    await Task.megaYield()

    subject.yield(1)
    subject.finish()
    subject.yield(2)

    await task.value

    XCTAssertEqual(values.value, [0, 1])
    XCTAssertEqual(subject.value, 1)
  }
}
