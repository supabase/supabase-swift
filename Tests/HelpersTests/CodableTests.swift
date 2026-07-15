//
//  CodableTests.swift
//
//
//  Created by Guilherme Souza on 15/07/26.
//

import Testing

@testable import Helpers

@Suite
struct DecodeOneOfTests {
  struct Failure: Error, Equatable {
    let id: Int
  }

  @Test
  func returnsFirstSuccess() throws {
    let result = try decodeOneOf(
      { 1 },
      { throw Failure(id: 2) }
    )
    #expect(result == 1)
  }

  @Test
  func skipsFailingAttemptsAndReturnsFirstSuccess() throws {
    let result = try decodeOneOf(
      { throw Failure(id: 1) },
      { 2 }
    )
    #expect(result == 2)
  }

  @Test
  func throwsAllErrorsInOrderWhenEveryAttemptFails() {
    #expect {
      try decodeOneOf(
        { throw Failure(id: 1) },
        { throw Failure(id: 2) },
        { throw Failure(id: 3) }
      ) as Int
    } throws: { error in
      guard let combined = error as? AllDecodingAttemptsFailedError else { return false }
      return combined.errors.map { ($0 as? Failure)?.id } == [1, 2, 3]
    }
  }
}
