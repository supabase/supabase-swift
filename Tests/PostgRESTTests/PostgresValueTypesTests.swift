//
//  PostgresValueTypesTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 10/10/26.
//

import Foundation
import Testing

@testable import PostgREST

@Suite
struct PostgresValueTypesTests {
  struct Row: _PostgrestRelation {
    static let relationName = "postgres_values"
    static let selectString = "*"

    var span: _PostgresRange<Int>
    var duration: _PostgresInterval
    var at: _PostgresTime
    var payload: _PostgresBytes

    struct Columns: Sendable {
      let span = _PostgrestColumn<Row, _PostgresRange<Int>>("span")
      let duration = _PostgrestColumn<Row, _PostgresInterval>("duration")
      let at = _PostgrestColumn<Row, _PostgresTime>("at")
      let payload = _PostgrestColumn<Row, _PostgresBytes>("payload")
    }

    static let columns = Columns()
  }

  private func rendered(_ filter: _PostgrestFilter<Row>) -> String {
    filter.queryItems().map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
  }

  /// Every operand is the text form, bare at top level. Quoted, a range or a `bytea` is a `22P02`.
  @Test
  func anOperandIsTheBareTextForm() {
    let columns = Row.columns
    #expect(rendered(columns.duration.eq("1 day")) == "duration=eq.1 day")
    #expect(rendered(columns.at.gt("12:00")) == "at=gt.12:00")
    #expect(rendered(columns.span.eq("[1,10)")) == "span=eq.[1,10)")
    #expect(
      rendered(columns.payload.eq(_PostgresBytes(Data([0xde, 0xad])))) == #"payload=eq.\xdead"#)
  }

  /// Inside a group or a list, a value with `,`, `)` or `\` is quoted and escaped; PostgREST
  /// unquotes it before Postgres parses it.
  @Test
  func anOperandIsQuotedInAGroupAndAList() {
    let columns = Row.columns
    #expect(
      rendered(columns.span.eq("[1,10)") || columns.duration.eq("1 day"))
        == #"or=(span.eq."[1,10)",duration.eq.1 day)"#)
    #expect(
      rendered(columns.payload.in([_PostgresBytes(Data([0x01])), _PostgresBytes(Data())]))
        == #"payload=in.("\\x01","\\x")"#)
  }

  @Test
  func bytesRoundTripThroughTheHexForm() throws {
    let bytes = _PostgresBytes(Data([0xde, 0xad, 0xbe, 0xef]))
    let encoded = try JSONEncoder().encode(bytes)
    #expect(String(decoding: encoded, as: UTF8.self) == #""\\xdeadbeef""#)
    #expect(try JSONDecoder().decode(_PostgresBytes.self, from: encoded) == bytes)
    #expect(_PostgresBytes.data(fromHex: #"\xDEAD"#) == Data([0xde, 0xad]))
    #expect(_PostgresBytes.data(fromHex: #"\x"#) == Data())
  }

  /// Base64, an odd digit count and a non-hex digit are not the form PostgREST sends.
  @Test
  func bytesRejectAnythingButHex() {
    #expect(_PostgresBytes.data(fromHex: "3q2+7w==") == nil)
    #expect(_PostgresBytes.data(fromHex: #"\x123"#) == nil)
    #expect(_PostgresBytes.data(fromHex: #"\xzz"#) == nil)
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(_PostgresBytes.self, from: Data(#""3q2+7w==""#.utf8))
    }
  }

  @Test
  func textTypesRoundTripAsStrings() throws {
    let span: _PostgresRange<Date> = "[2024-01-01,2024-02-01)"
    let data = try JSONEncoder().encode([span])
    #expect(try JSONDecoder().decode([_PostgresRange<Date>].self, from: data) == [span])
    #expect(
      try JSONDecoder().decode(_PostgresInterval.self, from: Data(#""1 day 02:00:00""#.utf8))
        == "1 day 02:00:00")
  }

  /// A composite comes back as an object and goes out unchanged.
  @Test
  func anUnmappedValueRoundTripsItsJSON() throws {
    let json = Data(#"{"amount":1,"currency":"USD"}"#.utf8)
    let value = try JSONDecoder().decode(_PostgresUnmapped.self, from: json)
    #expect(value == _PostgresUnmapped(["amount": 1, "currency": "USD"]))
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    #expect(try encoder.encode(value) == json)
  }
}
