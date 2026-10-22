//
//  FunctionStreamResponseTests.swift
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
struct FunctionStreamResponseTests {
  func makeResponse(body: String = "", headers: HTTPFields = [:]) -> FunctionStreamResponse {
    FunctionStreamResponse(status: .ok, headers: headers, body: HTTPBody(Data(body.utf8)))
  }

  @Test
  func headerDerivedProperties() {
    let response = makeResponse(
      headers: [
        .contentType: "text/event-stream",
        .xSbEdgeRegion: "eu-central-2",
        .xDenoExecutionID: "exec-1",
        .sbRequestID: "req-1",
      ])

    #expect(response.contentType == "text/event-stream")
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
  func descriptionNeverIncludesTheBody() {
    let response = makeResponse(
      body: "secret", headers: [.contentType: "text/event-stream"])

    #expect(
      response.description
        == "FunctionStreamResponse(status: 200, contentType: text/event-stream)")
    #expect(makeResponse().description == "FunctionStreamResponse(status: 200, contentType: none)")
  }
}
