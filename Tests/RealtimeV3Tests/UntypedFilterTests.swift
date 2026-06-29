//
//  UntypedFilterTests.swift
//  RealtimeV3Tests
//
//  Created by Guilherme Souza on 29/06/26.
//

import Foundation
import Testing

@testable import RealtimeV3

// MARK: - UntypedFilterTests

@Suite struct UntypedFilterTests {

  // MARK: - eqSerializes

  /// eq factory must produce `column=eq.value`.
  @Test func eqSerializes() {
    #expect(UntypedFilter.eq("room_id", 42).serialized == "room_id=eq.42")
  }

  // MARK: - neqSerializes

  /// neq factory must produce `column=neq.value`.
  @Test func neqSerializes() {
    #expect(UntypedFilter.neq("status", "closed").serialized == "status=neq.closed")
  }

  // MARK: - gtSerializes

  @Test func gtSerializes() {
    #expect(UntypedFilter.gt("score", 100).serialized == "score=gt.100")
  }

  // MARK: - gteSerializes

  @Test func gteSerializes() {
    #expect(UntypedFilter.gte("score", 100).serialized == "score=gte.100")
  }

  // MARK: - ltSerializes

  @Test func ltSerializes() {
    #expect(UntypedFilter.lt("age", 18).serialized == "age=lt.18")
  }

  // MARK: - lteSerializes

  @Test func lteSerializes() {
    #expect(UntypedFilter.lte("age", 18).serialized == "age=lte.18")
  }

  // MARK: - inSerializes

  /// in factory must produce `column=in.(v1,v2,v3)`.
  @Test func inSerializes() {
    #expect(UntypedFilter.in("id", [1, 2, 3]).serialized == "id=in.(1,2,3)")
  }

  // MARK: - inSingleValue

  @Test func inSingleValue() {
    #expect(UntypedFilter.in("id", [42]).serialized == "id=in.(42)")
  }

  // MARK: - inWith100Values

  /// Exactly 100 values must succeed.
  @Test func inWith100Values() {
    let values = (1...100).map { $0 }
    let expected = "id=in.(\(values.map { "\($0)" }.joined(separator: ",")))"
    #expect(UntypedFilter.in("id", values).serialized == expected)
  }

  // MARK: - likeSerializes

  @Test func likeSerializes() {
    #expect(UntypedFilter.like("name", "%alice%").serialized == "name=like.%alice%")
  }

  // MARK: - ilikeSerializes

  @Test func ilikeSerializes() {
    #expect(UntypedFilter.ilike("name", "%alice%").serialized == "name=ilike.%alice%")
  }

  // MARK: - matchSerializes

  @Test func matchSerializes() {
    #expect(UntypedFilter.match("name", "^alice").serialized == "name=match.^alice")
  }

  // MARK: - imatchSerializes

  @Test func imatchSerializes() {
    #expect(UntypedFilter.imatch("name", "^alice").serialized == "name=imatch.^alice")
  }

  // MARK: - isNullSerializes

  /// isNull must produce `column=is.null`.
  @Test func isNullSerializes() {
    #expect(UntypedFilter.isNull("deleted_at").serialized == "deleted_at=is.null")
  }

  // MARK: - isNotNullSerializes

  /// isNotNull must produce `column=not.is.null`.
  @Test func isNotNullSerializes() {
    #expect(UntypedFilter.isNotNull("deleted_at").serialized == "deleted_at=not.is.null")
  }

  // MARK: - isDistinctSerializes

  @Test func isDistinctSerializes() {
    #expect(UntypedFilter.isDistinct("status", "active").serialized == "status=isdistinct.active")
  }

  // MARK: - andJoinsWithComma

  /// and must join two clauses with a comma.
  @Test func andJoinsWithComma() {
    let filter = UntypedFilter.eq("a", 1).and(.eq("b", 2))
    #expect(filter.serialized == "a=eq.1,b=eq.2")
  }

  // MARK: - allJoinsMultiple

  /// all must join all clauses with commas.
  @Test func allJoinsMultiple() {
    let filter = UntypedFilter.all([.eq("a", 1), .eq("b", 2), .eq("c", 3)])
    #expect(filter.serialized == "a=eq.1,b=eq.2,c=eq.3")
  }

  // MARK: - notPrefixesOperator

  /// not must insert `not.` before the operator in each clause.
  @Test func notPrefixesOperator() {
    #expect(UntypedFilter.not(.eq("room_id", 42)).serialized == "room_id=not.eq.42")
  }

  // MARK: - notOnCompoundFilter

  /// not applied to a compound filter must prefix each clause.
  @Test func notOnCompoundFilter() {
    let compound = UntypedFilter.eq("a", 1).and(.eq("b", 2))
    let negated = UntypedFilter.not(compound)
    #expect(negated.serialized == "a=not.eq.1,b=not.eq.2")
  }

  // MARK: - notOnIsNull

  /// not on isNull must produce `column=not.is.null`.
  @Test func notOnIsNull() {
    #expect(UntypedFilter.not(.isNull("col")).serialized == "col=not.is.null")
  }

  // MARK: - stringValueQuoting

  /// String values that contain commas must be quoted for the `in` list.
  @Test func stringValueQuoting() {
    // A plain string value without special chars should not be quoted.
    #expect(UntypedFilter.eq("name", "alice").serialized == "name=eq.alice")
  }

  // MARK: - inStringValuesQuoted

  /// String values with commas inside an `in` list must be quoted.
  @Test func inStringValuesQuoted() {
    // "a,b" contains a comma so it must be double-quoted in the in() list.
    let result = UntypedFilter.in("tag", ["a,b", "c"]).serialized
    #expect(result == #"tag=in.("a,b",c)"#)
  }

  // MARK: - doubleValue

  @Test func doubleValue() {
    #expect(UntypedFilter.eq("price", 3.14).serialized == "price=eq.3.14")
  }

  // MARK: - boolValue

  @Test func boolValue() {
    #expect(UntypedFilter.eq("active", true).serialized == "active=eq.true")
  }

}
