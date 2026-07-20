//
//  EventEmitterTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 15/10/24.
//

import ConcurrencyExtras
import Helpers
import Testing

@Suite
struct EventEmitterTests {

  @Test
  func basics() {
    let sut = EventEmitter(initialEvent: "0")
    #expect(sut.emitsLastEventWhenAttaching)

    #expect(sut.lastEvent == "0")

    let receivedEvents = LockIsolated<[String]>([])

    let tokenA = sut.attach { value in
      receivedEvents.withValue { $0.append("a" + value) }
    }

    let tokenB = sut.attach { value in
      receivedEvents.withValue { $0.append("b" + value) }
    }

    sut.emit("1")
    sut.emit("2")
    sut.emit("3")
    sut.emit("4")

    sut.emit("5", to: tokenA)
    sut.emit("6", to: tokenB)

    tokenA.cancel()

    sut.emit("7")
    sut.emit("8")

    #expect(sut.lastEvent == "8")

    #expect(
      receivedEvents.value
        == ["a0", "b0", "a1", "b1", "a2", "b2", "a3", "b3", "a4", "b4", "a5", "b6", "b7", "b8"]
    )
  }

  @Test
  func dontEmitLastEventWhenAttaching() {
    let sut = EventEmitter(initialEvent: "0", emitsLastEventWhenAttaching: false)
    #expect(!sut.emitsLastEventWhenAttaching)

    let receivedEvent = LockIsolated<[String]>([])
    let token = sut.attach { value in
      receivedEvent.withValue { $0.append(value) }
    }

    sut.emit("1")

    #expect(receivedEvent.value == ["1"])

    token.cancel()
  }
}
