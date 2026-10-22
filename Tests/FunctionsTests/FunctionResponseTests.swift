//
//  FunctionResponseTests.swift
//  Functions
//
//  Created by Guilherme Souza on 05/10/26.
//

import Foundation
import HTTPTypes
import Helpers
import Testing

@testable import Functions

@Suite
struct FunctionResponseTests {
  func makeResponse(
    body: String = "", headers: HTTPFields = [:], decoder: JSONDecoder = .supabase()
  ) -> FunctionResponse {
    FunctionResponse(status: .ok, headers: headers, body: Data(body.utf8), decoder: decoder)
  }

  @Test
  func headerDerivedProperties() {
    let response = makeResponse(
      headers: [
        .contentType: "application/json",
        .xSbEdgeRegion: "eu-central-2",
        .xDenoExecutionID: "exec-1",
        .sbRequestID: "req-1",
      ])

    #expect(response.contentType == "application/json")
    #expect(response.region == .euCentral2)
    #expect(response.executionID == "exec-1")
    #expect(response.requestID == "req-1")
  }

  @Test
  func headerDerivedPropertiesAreNilWhenAbsent() {
    let response = makeResponse()

    #expect(response.contentType == nil)
    #expect(response.region == nil)
    #expect(response.executionID == nil)
    #expect(response.requestID == nil)
  }

  @Test
  func text() {
    #expect(makeResponse(body: "hello").text == "hello")
    #expect(
      FunctionResponse(status: .ok, headers: [:], body: Data([0xFF]), decoder: .supabase()).text
        == nil)
  }

  @Test
  func decodeUsesTheClientDecoderByDefault() throws {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    struct Payload: Decodable, Equatable {
      let userName: String
    }

    let response = makeResponse(body: #"{"user_name":"a"}"#, decoder: decoder)

    #expect(try response.decode(as: Payload.self) == Payload(userName: "a"))
    let inferred: Payload = try response.decode()
    #expect(inferred == Payload(userName: "a"))
  }

  @Test
  func perCallDecoderWins() throws {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    struct Payload: Decodable, Equatable {
      let userName: String
    }

    let response = makeResponse(body: #"{"user_name":"a"}"#)

    #expect(try response.decode(as: Payload.self, decoder: decoder) == Payload(userName: "a"))
  }

  @Test
  func decodeFailureIsADecodingError() {
    let response = makeResponse(body: "not json")

    do {
      _ = try response.decode(as: [String: String].self)
      Issue.record("Expected failure")
    } catch let error as FunctionsError {
      #expect(error.kind == .decoding)
      #expect(error.response == nil)
      #expect(error.underlyingError is DecodingError)
    } catch {
      Issue.record("Unexpected error \(error)")
    }
  }

  @Test
  func descriptionNeverPrintsTheBody() {
    let response = makeResponse(body: "secret", headers: [.contentType: "text/plain"])

    #expect(
      response.description == "FunctionResponse(status: 200, contentType: text/plain, bytes: 6)")
    #expect(!response.description.contains("secret"))
  }
}
