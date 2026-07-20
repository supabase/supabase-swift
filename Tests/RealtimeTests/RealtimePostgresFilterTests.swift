//
//  RealtimePostgresFilterTests.swift
//  Supabase
//
//  Created by Lucas Abijmil on 20/02/2025.
//

import XCTest

@testable import Realtime
@testable import RealtimeV2

final class RealtimePostgresFilterTests: XCTestCase {

  func testEq() {
    let value = "value"
    let column = "column"
    let filter: RealtimePostgresFilter = .eq(column, value: value)

    XCTAssertEqual(filter.value, "column=eq.value")
  }

  func testNeq() {
    let value = "value"
    let column = "column"
    let filter: RealtimePostgresFilter = .neq(column, value: value)

    XCTAssertEqual(filter.value, "column=neq.value")
  }

  func testGt() {
    let value = "value"
    let column = "column"
    let filter: RealtimePostgresFilter = .gt(column, value: value)

    XCTAssertEqual(filter.value, "column=gt.value")
  }

  func testGte() {
    let value = "value"
    let column = "column"
    let filter: RealtimePostgresFilter = .gte(column, value: value)

    XCTAssertEqual(filter.value, "column=gte.value")
  }

  func testLt() {
    let value = "value"
    let column = "column"
    let filter: RealtimePostgresFilter = .lt(column, value: value)

    XCTAssertEqual(filter.value, "column=lt.value")
  }

  func testLte() {
    let value = "value"
    let column = "column"
    let filter: RealtimePostgresFilter = .lte(column, value: value)

    XCTAssertEqual(filter.value, "column=lte.value")
  }

  func testIn() {
    let values = ["value1", "value2"]
    let column = "column"
    let filter: RealtimePostgresFilter = .in(column, values: values)

    XCTAssertEqual(filter.value, "column=in.(value1,value2)")
  }

  func testInDeduplicatesValues() {
    let filter: RealtimePostgresFilter = .in("status", values: ["a", "b", "a"])

    XCTAssertEqual(filter.value, "status=in.(a,b)")
  }

  func testLike() {
    let filter: RealtimePostgresFilter = .like("title", value: "%foo%")

    XCTAssertEqual(filter.value, "title=like.%foo%")
  }

  func testILike() {
    let filter: RealtimePostgresFilter = .ilike("title", value: "%foo%")

    XCTAssertEqual(filter.value, "title=ilike.%foo%")
  }

  func testMatch() {
    let filter: RealtimePostgresFilter = .match("title", value: "^foo")

    XCTAssertEqual(filter.value, "title=match.^foo")
  }

  func testIMatch() {
    let filter: RealtimePostgresFilter = .imatch("title", value: "^foo")

    XCTAssertEqual(filter.value, "title=imatch.^foo")
  }

  func testIs() {
    XCTAssertEqual(
      (.is("deleted_at", value: .null) as RealtimePostgresFilter).value, "deleted_at=is.null")
    XCTAssertEqual((.is("active", value: .true) as RealtimePostgresFilter).value, "active=is.true")
    XCTAssertEqual(
      (.is("active", value: .false) as RealtimePostgresFilter).value, "active=is.false")
    XCTAssertEqual(
      (.is("state", value: .unknown) as RealtimePostgresFilter).value, "state=is.unknown")
  }

  func testIsDistinct() {
    let filter: RealtimePostgresFilter = .isDistinct("value", value: 1)

    XCTAssertEqual(filter.value, "value=isdistinct.1")
  }

  func testNot() {
    let filter: RealtimePostgresFilter = .not(.eq("id", value: 1))

    XCTAssertEqual(filter.value, "id=not.eq.1")
  }

  func testNotIn() {
    let filter: RealtimePostgresFilter = .not(.in("status", values: ["draft", "archived"]))

    XCTAssertEqual(filter.value, "status=not.in.(draft,archived)")
  }

  func testAnd() {
    let filter: RealtimePostgresFilter = .and([
      .gt("amount", value: 100),
      .in("status", values: ["open", "pending"]),
    ])

    XCTAssertEqual(filter.value, "amount=gt.100,status=in.(open,pending)")
  }

  func testAndWithNot() {
    let filter: RealtimePostgresFilter = .and([
      .gt("amount", value: 100),
      .not(.in("status", values: ["draft", "archived"])),
      .like("title", value: "%foo%"),
    ])

    XCTAssertEqual(
      filter.value,
      "amount=gt.100,status=not.in.(draft,archived),title=like.%foo%"
    )
  }

  func testReservedCharacterQuoting() {
    XCTAssertEqual((.eq("name", value: "a,b") as RealtimePostgresFilter).value, #"name=eq."a,b""#)
    XCTAssertEqual((.eq("name", value: "a(b)") as RealtimePostgresFilter).value, #"name=eq."a(b)""#)
    XCTAssertEqual((.eq("name", value: " a") as RealtimePostgresFilter).value, #"name=eq." a""#)
  }

  func testReservedCharacterQuotingEscapesQuotesAndBackslashes() {
    XCTAssertEqual(
      (.eq("name", value: #"a"b\c"#) as RealtimePostgresFilter).value,
      #"name=eq."a\"b\\c""#
    )
  }

  func testReservedCharacterQuotingInList() {
    let filter: RealtimePostgresFilter = .in("tag", values: ["a,b", "c"])

    XCTAssertEqual(filter.value, #"tag=in.("a,b",c)"#)
  }
}
