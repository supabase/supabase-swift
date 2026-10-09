//
//  PostgrestJSONPathIntegrationTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 09/10/26.
//

import Foundation
@_spi(Experimental) import PostgrestMacros
import Testing

// `KeyValueStorage` is in `Generated.swift`. Each test writes its own rows under a unique key
// prefix and deletes them, so it does not see rows from the Realtime suite that shares the table.

/// The live half of `PostgrestDerivedColumnTests`' key and index cases: a quoted key reaches keys
/// that a bare operand cannot, and an `Int` reaches an array element.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct PostgrestJSONPathIntegrationTests {
  let client = PostgrestClient(
    url: URL(string: "\(DotEnv.supabaseURL)/rest/v1")!,
    headers: ["apikey": DotEnv.supabasePublishableKey]
  )

  @Test
  func keysAndIndexesReachTheirOwnValues() async throws {
    let prefix = "json-path-\(UUID().uuidString)"
    let object: JSONValue = ["0": "zero-key", "a.b": "dotted", #"q"t"#: "quote", "n": 10]
    let array: JSONValue = ["first", "last"]
    try await client.from("key_value_storage").insert(
      [
        ["key": .string("\(prefix)-object"), "value": object],
        ["key": .string("\(prefix)-array"), "value": array],
      ] as [JSONObject]
    ).execute()

    func keys(
      _ filter: (KeyValueStorage.Columns) -> _PostgrestFilter<KeyValueStorage>
    ) async throws -> [String] {
      try await client.from(KeyValueStorage.self).select()
        .where { $0.key.like("\(prefix)%") && filter($0) }
        .execute().value.map(\.key)
    }

    // A bare `->>0` would read index 0 of the array instead of the object's key.
    #expect(try await keys { $0.value.jsonText("0").eq("zero-key") } == ["\(prefix)-object"])
    #expect(try await keys { $0.value.jsonText(0).eq("first") } == ["\(prefix)-array"])
    #expect(try await keys { $0.value.jsonText(-1).eq("last") } == ["\(prefix)-array"])
    // A bare `->>a.b` is a PGRST100.
    #expect(try await keys { $0.value.jsonText("a.b").eq("dotted") } == ["\(prefix)-object"])
    #expect(try await keys { $0.value.jsonText(#"q"t"#).eq("quote") } == ["\(prefix)-object"])
    #expect(try await keys { $0.value.jsonObject("n").gt(2) } == ["\(prefix)-object"])

    try await client.from("key_value_storage").delete().like("key", pattern: "\(prefix)%")
      .execute()
  }

  /// Every operand shape `containsJSON` encodes, top level and inside `or=(…)`.
  @Test
  func containmentTakesEveryJSONShape() async throws {
    let prefix = "json-contains-\(UUID().uuidString)"
    let object: JSONValue = ["a": 1, "n": 10, "s": "x,y", "u": "a/b"]
    let array: JSONValue = ["x", 20]
    try await client.from("key_value_storage").insert(
      [
        ["key": .string("\(prefix)-object"), "value": object],
        ["key": .string("\(prefix)-array"), "value": array],
      ] as [JSONObject]
    ).execute()

    func keys(
      _ filter: (KeyValueStorage.Columns) -> _PostgrestFilter<KeyValueStorage>
    ) async throws -> [String] {
      try await client.from(KeyValueStorage.self).select()
        .where { $0.key.like("\(prefix)%") && filter($0) }
        .order { $0.key.asc() }
        .execute().value.map(\.key)
    }

    #expect(
      try await keys { $0.value.containsJSON(["s": "x,y", "u": "a/b"]) } == ["\(prefix)-object"])
    #expect(try await keys { $0.value.containsJSON([20]) } == ["\(prefix)-array"])
    #expect(try await keys { $0.value.containsJSON("x") } == ["\(prefix)-array"])
    #expect(
      try await keys {
        $0.value.containedByJSON(["a": 1, "n": 10, "s": "x,y", "u": "a/b", "z": 0])
      }
        == ["\(prefix)-object"])
    #expect(
      try await keys { $0.value.containsJSON(["a": 1, "n": 10]) || $0.value.containsJSON([20]) }
        == ["\(prefix)-array", "\(prefix)-object"])

    try await client.from("key_value_storage").delete().like("key", pattern: "\(prefix)%")
      .execute()
  }
}
