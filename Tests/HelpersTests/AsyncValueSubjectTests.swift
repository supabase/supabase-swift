//
//  AsyncValueSubjectTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 24/03/25.
//

import ConcurrencyExtras
import Testing

@testable import Helpers

@Suite
struct AsyncValueSubjectTests {

  @Test
  func initialValue() async {
    let subject = AsyncValueSubject<Int>(42)
    #expect(subject.value == 42)
  }

  @Test
  func yieldUpdatesValue() async {
    let subject = AsyncValueSubject<Int>(0)
    subject.yield(10)
    #expect(subject.value == 10)
  }

  @Test
  func valuesStream() async {
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

    #expect(values.value == [0, 1, 2, 3])
  }

  @Test
  func onChangeHandler() async {
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

    #expect(values.value == [0, 1, 2, 3])
  }

  @Test
  func finish() async {
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

    #expect(values.value == [0, 1])
    #expect(subject.value == 1)
  }
}
