//
//  JSONCodingTests.swift
//  HTTPRuntime
//
//  Created by Guilherme Souza on 25/08/26.
//

import Foundation
import Testing

@testable import HTTPRuntime

@Suite
struct JSONCodingTests {

  @Test
  func jsonValueRoundTrip() throws {
    let value = JSONValue.object([
      "s": .string("x"),
      "n": .number(3.5),
      "b": .bool(true),
      "arr": .array([.number(1), .null]),
    ])
    let data = try JSONCoding.encoder.encode(value)
    let decoded = try JSONCoding.decoder.decode(JSONValue.self, from: data)
    #expect(decoded == value)
  }

  @Test
  func iso8601DateCoding() throws {
    struct Holder: Codable, Equatable { let at: Date }
    let json = #"{"at":"2026-07-06T12:34:56.789Z"}"#
    let decoded = try JSONCoding.decoder.decode(Holder.self, from: Data(json.utf8))
    let reencoded = try JSONCoding.encoder.encode(decoded)
    let round = try JSONCoding.decoder.decode(Holder.self, from: reencoded)
    #expect(decoded == round)
  }
}
