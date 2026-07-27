//
//  RealtimePostgresFilterTests.swift
//  Supabase
//
//  Created by Lucas Abijmil on 20/02/2025.
//

import Testing

@testable import Realtime
@testable import RealtimeV2

@Suite
struct RealtimePostgresFilterTests {

  @Test
  func eq() {
    let value = "value"
    let column = "column"
    let filter: RealtimePostgresFilter = .eq(column, value: value)

    #expect(filter.value == "column=eq.value")
  }

  @Test
  func neq() {
    let value = "value"
    let column = "column"
    let filter: RealtimePostgresFilter = .neq(column, value: value)

    #expect(filter.value == "column=neq.value")
  }

  @Test
  func gt() {
    let value = "value"
    let column = "column"
    let filter: RealtimePostgresFilter = .gt(column, value: value)

    #expect(filter.value == "column=gt.value")
  }

  @Test
  func gte() {
    let value = "value"
    let column = "column"
    let filter: RealtimePostgresFilter = .gte(column, value: value)

    #expect(filter.value == "column=gte.value")
  }

  @Test
  func lt() {
    let value = "value"
    let column = "column"
    let filter: RealtimePostgresFilter = .lt(column, value: value)

    #expect(filter.value == "column=lt.value")
  }

  @Test
  func lte() {
    let value = "value"
    let column = "column"
    let filter: RealtimePostgresFilter = .lte(column, value: value)

    #expect(filter.value == "column=lte.value")
  }

  @Test
  func `in`() {
    let values = ["value1", "value2"]
    let column = "column"
    let filter: RealtimePostgresFilter = .in(column, values: values)

    #expect(filter.value == "column=in.(value1,value2)")
  }

  @Test
  func inDeduplicatesValues() {
    let filter: RealtimePostgresFilter = .in("status", values: ["a", "b", "a"])

    #expect(filter.value == "status=in.(a,b)")
  }

  @Test
  func like() {
    let filter: RealtimePostgresFilter = .like("title", value: "%foo%")

    #expect(filter.value == "title=like.%foo%")
  }

  @Test
  func iLike() {
    let filter: RealtimePostgresFilter = .ilike("title", value: "%foo%")

    #expect(filter.value == "title=ilike.%foo%")
  }

  @Test
  func match() {
    let filter: RealtimePostgresFilter = .match("title", value: "^foo")

    #expect(filter.value == "title=match.^foo")
  }

  @Test
  func iMatch() {
    let filter: RealtimePostgresFilter = .imatch("title", value: "^foo")

    #expect(filter.value == "title=imatch.^foo")
  }

  @Test
  func `is`() {
    #expect(
      (.is("deleted_at", value: .null) as RealtimePostgresFilter).value == "deleted_at=is.null")
    #expect((.is("active", value: .true) as RealtimePostgresFilter).value == "active=is.true")
    #expect((.is("active", value: .false) as RealtimePostgresFilter).value == "active=is.false")
    #expect((.is("state", value: .unknown) as RealtimePostgresFilter).value == "state=is.unknown")
  }

  @Test
  func isDistinct() {
    let filter: RealtimePostgresFilter = .isDistinct("value", value: 1)

    #expect(filter.value == "value=isdistinct.1")
  }

  @Test
  func not() {
    let filter: RealtimePostgresFilter = .not(.eq("id", value: 1))

    #expect(filter.value == "id=not.eq.1")
  }

  @Test
  func notIn() {
    let filter: RealtimePostgresFilter = .not(.in("status", values: ["draft", "archived"]))

    #expect(filter.value == "status=not.in.(draft,archived)")
  }

  @Test
  func and() {
    let filter: RealtimePostgresFilter = .and([
      .gt("amount", value: 100),
      .in("status", values: ["open", "pending"]),
    ])

    #expect(filter.value == "amount=gt.100,status=in.(open,pending)")
  }

  @Test
  func andWithNot() {
    let filter: RealtimePostgresFilter = .and([
      .gt("amount", value: 100),
      .not(.in("status", values: ["draft", "archived"])),
      .like("title", value: "%foo%"),
    ])

    #expect(
      filter.value
        == "amount=gt.100,status=not.in.(draft,archived),title=like.%foo%"
    )
  }

  @Test
  func reservedCharacterQuoting() {
    #expect((.eq("name", value: "a,b") as RealtimePostgresFilter).value == #"name=eq."a,b""#)
    #expect((.eq("name", value: "a(b)") as RealtimePostgresFilter).value == #"name=eq."a(b)""#)
    #expect((.eq("name", value: " a") as RealtimePostgresFilter).value == #"name=eq." a""#)
  }

  @Test
  func reservedCharacterQuotingEscapesQuotesAndBackslashes() {
    #expect(
      (.eq("name", value: #"a"b\c"#) as RealtimePostgresFilter).value
        == #"name=eq."a\"b\\c""#
    )
  }

  @Test
  func reservedCharacterQuotingInList() {
    let filter: RealtimePostgresFilter = .in("tag", values: ["a,b", "c"])

    #expect(filter.value == #"tag=in.("a,b",c)"#)
  }
}
