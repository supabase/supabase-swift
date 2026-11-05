//
//  FunctionsIsolationTests.swift
//  DefaultIsolationTests
//
//  Created by Guilherme Souza on 05/11/26.
//

import Foundation
import Supabase

/// Calls every public async Functions API from the main actor, since this target compiles with
/// `.defaultIsolation(MainActor.self)`. Nothing here runs: if a call stops compiling, the build
/// fails. `scripts/check-isolation-coverage.sh` checks that each API has a call.
enum FunctionsIsolationTests {
  /// A request body with a main-actor-isolated `Encodable` conformance.
  struct Prompt: Encodable {
    var text: String
  }

  /// A result with a main-actor-isolated `Decodable` conformance.
  struct Answer: Decodable {
    var text: String
  }

  static func functions(_ functions: FunctionsClient) async throws {
    _ = try await functions.invoke("function")
    _ = try await functions.invoke("function", body: .json(Prompt(text: "hi")))
    _ = try await functions.invoke("function", body: .text("hi"), options: .init())
    let answer: Answer = try await functions.invoke(
      "function", body: .json(Prompt(text: "hi")))
    _ = answer.text
    _ = try await functions.invoke("function", as: Answer.self)
    _ = try await functions.invoke("function", as: Answer.self, decoder: JSONDecoder())

    let streamed = try await functions.stream("function")
    for try await chunk in streamed.body { _ = chunk }
    let streamedWithBody = try await functions.stream(
      "function", body: .json(Prompt(text: "hi")), options: .init())
    for try await chunk in streamedWithBody.body { _ = chunk }
  }
}
