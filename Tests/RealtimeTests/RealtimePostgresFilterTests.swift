//
//  RealtimePostgresFilterTests.swift
//  Supabase
//
//  Created by Lucas Abijmil on 20/02/2025.
//

import XCTest

@testable import Realtime

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
}
