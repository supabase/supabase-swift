//
//  MessageTests.swift
//
//
//  Created by Guilherme Souza on 23/11/23.
//

@testable import Realtime
import XCTest

final class MessageTests: XCTestCase {
  func testDecodable() throws {
    let raw = #"[null,null,"realtime:public","INSERT",{"value": 1}]"#.data(using: .utf8)!

    let message = try JSONDecoder().decode(Message.self, from: raw)

    XCTAssertEqual(
      message,
      Message(
        ref: "",
        topic: "realtime:public",
        event: "INSERT",
        payload: [
          "value": .number(1),
        ],
        joinRef: nil
      )
    )
  }

  func testEncodable() throws {
    let message = Message(
      ref: "1",
      topic: "realtime:public",
      event: "INSERT",
      payload: [
        "value": .number(1),
      ],
      joinRef: nil
    )

    let data = try JSONEncoder().encode(message)

    let raw = String(data: data, encoding: .utf8)
    XCTAssertEqual(raw, #"[null,"1","realtime:public","INSERT",{"value":1}]"#)
  }

  func testPayloadWithResponse() {
    let message = Message(
      ref: "1",
      topic: "realtime:public",
      event: "INSERT",
      payload: [
        "response": .object([
          "value": .number(1),
        ]),
      ],
      joinRef: nil
    )

    let payload = message.payload
    XCTAssertEqual(payload, ["value": .number(1)])
  }

  func testPayloadWithStatus() {
    let message = Message(
      ref: "1",
      topic: "realtime:public",
      event: "INSERT",
      payload: [
        "status": .string("ok"),
      ],
      joinRef: nil
    )

    let status = message.status
    XCTAssertEqual(status, .ok)
  }
}
