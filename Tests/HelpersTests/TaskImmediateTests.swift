//
//  TaskImmediateTests.swift
//  HelpersTests
//
//  Created by Guilherme Souza on 19/10/26.
//

import Testing

@testable import Helpers

@Suite
struct TaskImmediateTests {
  actor Counter {
    var value = 0
    var sawPrefix = false

    func increment() { value += 1 }

    /// The body mutates isolated state without `await`: it inherits this actor's isolation.
    func start() -> Task<Void, Never> {
      Task.immediateIfAvailable {
        sawPrefix = true
        await Task.yield()
        value += 1
      }
    }
  }

  @Test
  func bodyInheritsTheCallersActorAndCompletes() async {
    let counter = Counter()
    let task = await counter.start()
    await task.value
    #expect(await counter.value == 1)
    #expect(await counter.sawPrefix)
  }

  @Test
  func synchronousPrefixRunsBeforeTheCallReturnsWhenImmediateIsAvailable() async {
    guard #available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
    let counter = Counter()
    let task = await counter.start()
    // `sawPrefix` is set before the body's first suspension point, and `Task.immediate` ran
    // that prefix inline, so no yield is needed to observe it.
    #expect(await counter.sawPrefix)
    await task.value
  }

  @Test
  func throwingVariantPropagatesTheError() async {
    struct Failure: Error {}
    let task = Task<Void, any Error>.immediateIfAvailable {
      throw Failure()
    }
    await #expect(throws: Failure.self) { try await task.value }
  }
}
