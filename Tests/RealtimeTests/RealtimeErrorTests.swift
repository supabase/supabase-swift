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

@Suite
struct RealtimeErrorTests {
  @Test
  func errorDescriptionIsTheMessage() {
    let error = RealtimeError(kind: .transport, message: "Connection failed")

    #expect(error.errorDescription == "Connection failed")
    #expect(error.localizedDescription == "Connection failed")
  }

  @Test
  func statics() {
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

  // MARK: - Server reason classification (SDK-2098)

  struct JoinReasonRow: CustomTestStringConvertible {
    let reason: String
    let code: RealtimeError.ServerCode?
    let kind: RealtimeError.Kind
    let isRetryable: Bool
    var testDescription: String { reason }
  }

  static let joinReasons: [JoinReasonRow] = [
    // fatal
    .init(
      reason: "TopicNameRequired: You must provide a topic name",
      code: .topicNameRequired, kind: .server, isRetryable: false),
    .init(
      reason: "InvalidJWTToken: Fields `role` and `exp` are required in JWT",
      code: .invalidJWTToken, kind: .unauthorized, isRetryable: false),
    .init(
      reason: "InvalidJWTToken: Token expiration time is invalid",
      code: .invalidJWTToken, kind: .unauthorized, isRetryable: false),
    .init(
      reason: "MalformedJWT: The token provided is not a valid JWT",
      code: .malformedJWT, kind: .unauthorized, isRetryable: false),
    .init(
      reason: "JwtSignatureError: Failed to validate JWT signature",
      code: .jwtSignatureError, kind: .unauthorized, isRetryable: false),
    .init(
      reason: "JwtSignerError: Failed to generate JWT signer",
      code: .jwtSignerError, kind: .unauthorized, isRetryable: false),
    .init(
      reason: "Unauthorized: You do not have permissions to read from this Channel topic: room",
      code: .unauthorized, kind: .unauthorized, isRetryable: false),
    .init(
      reason: "PrivateOnly: This project only allows private channels",
      code: .privateOnly, kind: .server, isRetryable: false),
    .init(
      reason: "TenantNotFound: Tenant with the given ID does not exist",
      code: .tenantNotFound, kind: .server, isRetryable: false),
    .init(
      reason: "RealtimeDisabledForTenant: Realtime disabled for this tenant",
      code: .realtimeDisabledForTenant, kind: .server, isRetryable: false),
    .init(
      reason: "RealtimeDisabledForConfiguration: bad cdc params",
      code: .realtimeDisabledForConfiguration, kind: .server, isRetryable: false),
    .init(
      reason: "UnableToReplayMessages: Replay is not allowed for public channels",
      code: .unableToReplayMessages, kind: .server, isRetryable: false),
    // auth refresh
    .init(
      reason: "InvalidJWTToken: Token has expired 12 seconds ago",
      code: .invalidJWTToken, kind: .unauthorized, isRetryable: true),
    // rate limit
    .init(
      reason: "ChannelRateLimitReached: Too many channels",
      code: .channelRateLimitReached, kind: .rateLimited, isRetryable: true),
    .init(
      reason: "ConnectionRateLimitReached: Too many connected users",
      code: .connectionRateLimitReached, kind: .rateLimited, isRetryable: true),
    .init(
      reason: "ClientJoinRateLimitReached: Too many joins per second",
      code: .clientJoinRateLimitReached, kind: .rateLimited, isRetryable: true),
    // retry
    .init(
      reason: "RealtimeRestarting: Realtime is restarting, please standby",
      code: .realtimeRestarting, kind: .server, isRetryable: true),
    .init(
      reason: "InitializingProjectConnection: Connecting to the project database",
      code: .initializingProjectConnection, kind: .server, isRetryable: true),
    .init(
      reason: "IncreaseConnectionPool: Please increase your connection pool size",
      code: .increaseConnectionPool, kind: .server, isRetryable: true),
    .init(
      reason: "DatabaseLackOfConnections: Database can't accept more connections",
      code: .databaseLackOfConnections, kind: .server, isRetryable: true),
    .init(
      reason: "DatabaseConnectionRateLimitReached: Too many database connections attempts",
      code: .databaseConnectionRateLimitReached, kind: .rateLimited, isRetryable: true),
    .init(
      reason: "UnableToConnectToProject: Realtime was unable to connect to the project database",
      code: .unableToConnectToProject, kind: .server, isRetryable: true),
    .init(
      reason: "QueryCanceled: Query was cancelled, please try again",
      code: .queryCanceled, kind: .server, isRetryable: true),
    .init(
      reason: "MissingPartition: partition missing",
      code: .missingPartition, kind: .server, isRetryable: true),
    .init(
      reason: "TimeoutOnRpcCall: Node request timeout",
      code: .timeoutOnRpcCall, kind: .server, isRetryable: true),
    .init(
      reason: "ErrorOnRpcCall: RPC call error: boom",
      code: .errorOnRpcCall, kind: .server, isRetryable: true),
    .init(
      reason: "PostgresChangesSubscribeTimeout: Timed out after 15000ms",
      code: .postgresChangesSubscribeTimeout, kind: .server, isRetryable: true),
    .init(
      reason: "UnknownErrorOnChannel: %RuntimeError{}",
      code: .unknownErrorOnChannel, kind: .server, isRetryable: true),
    .init(
      reason: "SomeCodeThisSDKDoesNotKnow: details",
      code: "SomeCodeThisSDKDoesNotKnow", kind: .server, isRetryable: true),
    // bare strings, no code
    .init(
      reason: "Realtime was unable to connect to the project database",
      code: nil, kind: .server, isRetryable: true),
    .init(reason: "Unknown Error on Channel", code: nil, kind: .server, isRetryable: true),
  ]

  @Test(arguments: joinReasons)
  func joinErrorClassifiesEveryServerReason(row: JoinReasonRow) {
    let error = RealtimeError.joinError(reason: row.reason)

    #expect(error.serverCode == row.code)
    #expect(error.kind == row.kind)
    #expect(error.isRetryable == row.isRetryable)
    #expect(error.message == row.reason)
  }

  @Test
  func joinErrorDoesNotTreatAProseSentenceWithAColonAsACode() {
    let error = RealtimeError.joinError(reason: "Something went wrong: details")

    #expect(error.serverCode == nil)
    #expect(error.isRetryable)
  }

  @Test
  func ackErrorMapsPayloadSizeExceededToPayloadTooLarge() {
    let error = RealtimeError.ackError(reason: "payload_size_exceeded")

    #expect(error.kind == .payloadTooLarge)
    #expect(!error.isRetryable)
    #expect(error.serverCode == nil)
  }

  @Test
  func ackErrorWithAnUnknownReasonIsAServerError() {
    let error = RealtimeError.ackError(reason: "something else")

    #expect(error.kind == .server)
    #expect(error.message == "something else")
  }

  @Test
  func socketClosedCarriesTheCloseCodeAndIsRetryable() {
    let error = RealtimeError.socketClosed(code: WebSocketCloseCode(rawValue: 1006), reason: "x")

    #expect(error.kind == .transport)
    #expect(error.closeCode == WebSocketCloseCode(rawValue: 1006))
    #expect(error.isRetryable)
    #expect(error.message.contains("1006"))
    #expect(error.message.contains("x"))
  }

  @Test
  func socketClosedWithoutACodeOrReasonStillHasAMessage() {
    let error = RealtimeError.socketClosed(code: nil, reason: nil)

    #expect(error.closeCode == nil)
    #expect(!error.message.isEmpty)
  }

  @Test(arguments: [401, 403, 404])
  func upgradeFailedIsFatalForAuthAndNotFoundStatuses(status: Int) {
    let error = RealtimeError.upgradeFailed(status: status)

    #expect(error.kind == .transport)
    #expect(!error.isRetryable)
    #expect(error.message.contains("\(status)"))
  }

  @Test(arguments: [429, 500, 502, 503])
  func upgradeFailedIsRetryableForRateLimitAndServerStatuses(status: Int) {
    let error = RealtimeError.upgradeFailed(status: status)

    #expect(error.kind == .transport)
    #expect(error.isRetryable)
  }

  @Test
  func initDefaultsToRetryableWithNoCodes() {
    let error = RealtimeError(kind: .timeout, message: "slow")

    #expect(error.isRetryable)
    #expect(error.serverCode == nil)
    #expect(error.closeCode == nil)
  }
}
