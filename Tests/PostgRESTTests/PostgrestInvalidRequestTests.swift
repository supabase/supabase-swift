//
//  PostgrestInvalidRequestTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 09/11/26.
//

import Foundation
import Testing

@_spi(Experimental) import PostgREST

/// A body the default encoder refuses: `JSONEncoder` throws on a non-finite `Double`.
@Suite
struct PostgrestInvalidRequestTests {
  struct Reading: _PostgrestWritableRelation {
    static let relationName = "readings"
    static let selectString = "*"

    var value: Double

    struct Columns: Sendable {
      let value = _PostgrestColumn<Reading, Double>("value")
    }
    static let columns = Columns()

    struct Draft: Encodable, Sendable {
      var value: Double
    }
  }

  struct Record: _PostgrestFunction {
    typealias Result = Int
    static let functionName = "record"
    var value: Double
  }

  let client: PostgrestClient

  init() throws {
    client = try PostgrestClient(
      configuration: .init(url: URL(string: "https://example.supabase.co")!))
  }

  let nonFiniteValue = ["value": Double.nan]

  static func isInvalidRequest(_ error: any Error) -> Bool {
    guard let error = error as? PostgrestError else { return false }
    return error.kind == .invalidRequest && error.underlyingError is EncodingError
  }

  @Test
  func insertWrapsAnEncodingFailure() {
    #expect { try client.from("readings").insert(nonFiniteValue) } throws: {
      Self.isInvalidRequest($0)
    }
  }

  @Test
  func upsertWrapsAnEncodingFailure() {
    #expect { try client.from("readings").upsert(nonFiniteValue) } throws: {
      Self.isInvalidRequest($0)
    }
  }

  @Test
  func updateWrapsAnEncodingFailure() {
    #expect { try client.from("readings").update(nonFiniteValue) } throws: {
      Self.isInvalidRequest($0)
    }
  }

  @Test
  func rpcWrapsAnEncodingFailure() {
    #expect { try client.rpc("record", params: nonFiniteValue) } throws: {
      Self.isInvalidRequest($0)
    }
  }

  @Test
  func typedInsertWrapsAnEncodingFailure() {
    #expect { try client.from(Reading.self).insert(Reading.Draft(value: .nan)) } throws: {
      Self.isInvalidRequest($0)
    }
  }

  @Test
  func typedUpdateWrapsAnEncodingFailure() {
    #expect { try client.from(Reading.self).update { $0.value = .nan } } throws: {
      Self.isInvalidRequest($0)
    }
  }

  @Test
  func typedRPCWrapsAnEncodingFailure() {
    #expect { try client.rpc(Record(value: .nan)) } throws: {
      Self.isInvalidRequest($0)
    }
  }
}
