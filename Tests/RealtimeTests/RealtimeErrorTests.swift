//
//  RealtimeErrorTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 29/07/25.
//

import Foundation
import HTTPTypes
import Testing

@testable import Realtime
@testable import RealtimeV2

@Suite
struct RealtimeErrorTests {
  @Test
  func errorDescriptionIsTheMessage() {
    let error = RealtimeError(kind: .connection, message: "Connection failed")

    #expect(error.errorDescription == "Connection failed")
    #expect(error.localizedDescription == "Connection failed")
  }

  @Test
  func statics() {
    #expect(RealtimeError.maxRetryAttemptsReached.kind == .maxRetryAttemptsReached)
    #expect(RealtimeError.maxRetryAttemptsReached.message == "Maximum retry attempts reached.")
    #expect(RealtimeError.channelClosedByServer.kind == .channelClosedByServer)
    #expect(RealtimeError.accessTokenMissing.kind == .accessTokenMissing)
    #expect(RealtimeError.heartbeatTimeout.kind == .timeout)
  }

  @Test
  func descriptionIncludesKindAndStatus() {
    let error = RealtimeError(
      kind: .server,
      message: "Server error",
      response: HTTPErrorResponse(statusCode: 500, headers: HTTPFields(), body: Data())
    )

    #expect(error.description == "RealtimeError(server): Server error [status 500]")
  }

  @Test
  func isPublicAndConformsToSupabaseError() {
    let error: any Error = RealtimeError(kind: .decoding, message: "bad frame")

    #expect((error as? any SupabaseError)?.message == "bad frame")
  }
}
