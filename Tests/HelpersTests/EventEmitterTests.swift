//
//  EventEmitterTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 15/10/24.
//

import ConcurrencyExtras
import XCTest

import Helpers

final class EventEmitterTests: XCTestCase {

  func testBasics() {
    let sut = EventEmitter(initialEvent: "0")
    XCTAssertTrue(sut.emitsLastEventWhenAttaching)

    XCTAssertEqual(sut.lastEvent, "0")

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

    XCTAssertEqual(sut.lastEvent, "8")

    XCTAssertEqual(
      receivedEvents.value,
      ["a0", "b0", "a1", "b1", "a2", "b2", "a3", "b3", "a4", "b4", "a5", "b6", "b7", "b8"]
    )
  }

  func test_dontEmitLastEventWhenAttaching() {
    let sut = EventEmitter(initialEvent: "0", emitsLastEventWhenAttaching: false)
    XCTAssertFalse(sut.emitsLastEventWhenAttaching)

    let receivedEvent = LockIsolated<[String]>([])
    let token = sut.attach { value in
      receivedEvent.withValue { $0.append(value) }
    }

    sut.emit("1")

    XCTAssertEqual(receivedEvent.value, ["1"])

    token.cancel()
  }
}
