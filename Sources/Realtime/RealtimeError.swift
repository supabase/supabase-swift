//
//  RealtimeError.swift
//
//
//  Created by Guilherme Souza on 30/10/23.
//

import Foundation
public import Helpers

/// An error thrown by the Realtime client and channels.
///
/// Check ``kind`` to learn what failed. ``serverCode`` carries the code the server put in
/// front of a join or channel error reason. ``isRetryable`` says whether the same call can
/// succeed later without the caller changing anything. ``response`` is set only for
/// ``Kind-swift.struct/server`` errors from the REST broadcast endpoint used by `httpSend`.
/// WebSocket failures carry the transport error in ``underlyingError`` when there is one.
///
/// ```swift
/// do {
///   try await channel.subscribeWithError()
/// } catch let error as RealtimeError where error.kind == .unauthorized {
///   signInAgain()
/// }
/// ```
public struct RealtimeError: SupabaseError {
  /// What failed. Compare against the static members and keep a fallback branch.
  public struct Kind: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
      self.init(rawValue: value)
    }

    /// A subscribe, push, heartbeat or REST broadcast did not complete within the configured
    /// timeout. Retry, or raise the timeout setting if it happens often.
    public static let timeout: Kind = "timeout"
    /// A send was attempted on a channel that is not subscribed. Call `subscribe()` first.
    public static let notSubscribed: Kind = "notSubscribed"
    /// The socket went away while a reply was pending. The engine reconnects on its own; retry
    /// the call once the status is back to connected.
    public static let notConnected: Kind = "notConnected"
    /// `httpSend` needs an access token and none was available. Sign in, or pass an
    /// `accessToken` closure, before sending. No request was sent.
    public static let accessTokenMissing: Kind = "accessTokenMissing"
    /// The server rejected the token or the topic's RLS policy denied access. Retrying as-is
    /// will not help; ``RealtimeError/serverCode`` says which check failed.
    public static let unauthorized: Kind = "unauthorized"
    /// The server applied a rate limit. ``RealtimeError/serverCode`` names which one. The engine
    /// backs off before trying again.
    public static let rateLimited: Kind = "rateLimited"
    /// The server closed the channel (`phx_close`) with a `system` error. The message carries
    /// the server's reason.
    public static let channelClosed: Kind = "channelClosed"
    /// A broadcast with `ack` was rejected because the payload is over the project's limit.
    public static let payloadTooLarge: Kind = "payloadTooLarge"
    /// The server answered a join or REST broadcast with an error this SDK has no narrower kind
    /// for. Read ``RealtimeError/serverCode`` and ``RealtimeError/message``, or
    /// ``RealtimeError/response`` on the REST path.
    public static let server: Kind = "server"
    /// The network path failed: a REST broadcast never completed, the WebSocket upgrade was
    /// refused, or the socket closed. ``RealtimeError/underlyingError`` is the `URLError` when
    /// there was one; `closeCode` the close status when the socket closed.
    public static let transport: Kind = "transport"
    /// A frame from the server could not be decoded, or a message had an unexpected shape.
    /// Nothing to retry; report it.
    public static let decoding: Kind = "decoding"

    /// A frame could not be encoded for sending. Never thrown to callers; it only appears in logs.
    static let encoding: Kind = "encoding"
  }

  /// The code the server prefixes to a join or channel error reason, as in
  /// `"Unauthorized: You do not have permissions…"`.
  ///
  /// The server owns this set and adds to it without notice, so compare against the static
  /// members and keep a fallback branch.
  public struct ServerCode: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
      self.init(rawValue: value)
    }

    public static let topicNameRequired: ServerCode = "TopicNameRequired"
    public static let invalidJWTToken: ServerCode = "InvalidJWTToken"
    public static let malformedJWT: ServerCode = "MalformedJWT"
    public static let jwtSignatureError: ServerCode = "JwtSignatureError"
    public static let jwtSignerError: ServerCode = "JwtSignerError"
    public static let unauthorized: ServerCode = "Unauthorized"
    public static let privateOnly: ServerCode = "PrivateOnly"
    public static let tenantNotFound: ServerCode = "TenantNotFound"
    public static let realtimeDisabledForTenant: ServerCode = "RealtimeDisabledForTenant"
    public static let realtimeDisabledForConfiguration: ServerCode =
      "RealtimeDisabledForConfiguration"
    public static let unableToReplayMessages: ServerCode = "UnableToReplayMessages"
    public static let channelRateLimitReached: ServerCode = "ChannelRateLimitReached"
    public static let connectionRateLimitReached: ServerCode = "ConnectionRateLimitReached"
    public static let clientJoinRateLimitReached: ServerCode = "ClientJoinRateLimitReached"
    public static let realtimeRestarting: ServerCode = "RealtimeRestarting"
    public static let initializingProjectConnection: ServerCode = "InitializingProjectConnection"
    public static let increaseConnectionPool: ServerCode = "IncreaseConnectionPool"
    public static let databaseLackOfConnections: ServerCode = "DatabaseLackOfConnections"
    public static let databaseConnectionRateLimitReached: ServerCode =
      "DatabaseConnectionRateLimitReached"
    public static let unableToConnectToProject: ServerCode = "UnableToConnectToProject"
    public static let queryCanceled: ServerCode = "QueryCanceled"
    public static let missingPartition: ServerCode = "MissingPartition"
    public static let timeoutOnRpcCall: ServerCode = "TimeoutOnRpcCall"
    public static let errorOnRpcCall: ServerCode = "ErrorOnRpcCall"
    public static let postgresChangesSubscribeTimeout: ServerCode =
      "PostgresChangesSubscribeTimeout"
    public static let unknownErrorOnChannel: ServerCode = "UnknownErrorOnChannel"

    /// Codes the server emits for conditions the caller must fix: a bad token, a denied
    /// policy, a disabled tenant, invalid replay parameters. Retrying as-is cannot succeed.
    ///
    /// The server's catalog at https://github.com/supabase/realtime/blob/main/ERROR_CODES.md
    /// lists codes without saying which are permanent, so these sets are this SDK's policy: a
    /// code is fatal when the server would give the same answer on retry; the rest retries.
    static let fatal: Set<ServerCode> = [
      .topicNameRequired, .malformedJWT, .jwtSignatureError, .jwtSignerError, .invalidJWTToken,
      .unauthorized, .privateOnly, .tenantNotFound, .realtimeDisabledForTenant,
      .realtimeDisabledForConfiguration, .unableToReplayMessages,
    ]

    static let authentication: Set<ServerCode> = [
      .unauthorized, .invalidJWTToken, .malformedJWT, .jwtSignatureError, .jwtSignerError,
    ]

    static let rateLimit: Set<ServerCode> = [
      .channelRateLimitReached, .connectionRateLimitReached, .clientJoinRateLimitReached,
      .databaseConnectionRateLimitReached,
    ]

    /// The code in front of the first `": "`, or `nil` for the server's bare-string reasons.
    /// A prefix with whitespace is prose, not a code.
    static func parse(_ reason: String) -> ServerCode? {
      guard let separator = reason.range(of: ": ") else { return nil }
      let prefix = reason[..<separator.lowerBound]
      guard !prefix.isEmpty, !prefix.contains(where: \.isWhitespace) else { return nil }
      return ServerCode(rawValue: String(prefix))
    }
  }

  public var kind: Kind
  public var message: String
  /// The code parsed from a server error reason, when the reason carried one.
  public var serverCode: ServerCode?
  /// The close status, when a WebSocket close caused this error.
  package var closeCode: WebSocketCloseCode?
  /// Whether the same operation can succeed later without the caller changing anything.
  ///
  /// `false` for errors the user must act on: a rejected token, a denied policy, a refused
  /// upgrade with 401/403/404. The engine never retries those on its own.
  public var isRetryable: Bool
  public var response: HTTPErrorResponse?
  public var underlyingError: (any Error)?

  public init(
    kind: Kind,
    message: String,
    serverCode: ServerCode? = nil,
    isRetryable: Bool = true,
    response: HTTPErrorResponse? = nil,
    underlyingError: (any Error)? = nil
  ) {
    self.kind = kind
    self.message = message
    self.serverCode = serverCode
    self.isRetryable = isRetryable
    self.response = response
    self.underlyingError = underlyingError
  }

  public var description: String {
    formattedDescription(kind: kind.rawValue)
  }
}

extension RealtimeError {
  static let accessTokenMissing = RealtimeError(
    kind: .accessTokenMissing, message: "Access token is required for httpSend()",
    isRetryable: false)

  static let heartbeatTimeout = RealtimeError(kind: .timeout, message: "heartbeat timeout")

  static func decoding(_ message: String) -> RealtimeError {
    RealtimeError(kind: .decoding, message: message, isRetryable: false)
  }

  static func encoding(_ message: String) -> RealtimeError {
    RealtimeError(kind: .encoding, message: message, isRetryable: false)
  }

  static func transport(_ message: String, underlyingError: (any Error)? = nil) -> RealtimeError {
    RealtimeError(kind: .transport, message: message, underlyingError: underlyingError)
  }

  /// The error for a `phx_reply` with `status: "error"` to a `phx_join`.
  ///
  /// `reason` is the server's `response.reason`, `"<Code>: <message>"` or one of the two
  /// bare strings. An expired-token `InvalidJWTToken` is retryable because a fresh token can
  /// fix it; every other fatal code is not.
  package static func joinError(reason: String) -> RealtimeError {
    let code = ServerCode.parse(reason)
    let kind: Kind
    switch code {
    case .some(let code) where ServerCode.authentication.contains(code): kind = .unauthorized
    case .some(let code) where ServerCode.rateLimit.contains(code): kind = .rateLimited
    default: kind = .server
    }
    let isExpiredToken = code == .invalidJWTToken && reason.contains("expired")
    let isRetryable = code.map { !ServerCode.fatal.contains($0) || isExpiredToken } ?? true
    return RealtimeError(kind: kind, message: reason, serverCode: code, isRetryable: isRetryable)
  }

  /// The error for a `phx_reply` with `status: "error"` to a broadcast sent with `ack`.
  ///
  /// The server answers a payload over the project's size limit with the bare string
  /// `"payload_size_exceeded"`; anything else is reported as it came.
  package static func ackError(reason: String) -> RealtimeError {
    if reason == "payload_size_exceeded" {
      return RealtimeError(
        kind: .payloadTooLarge, message: "Broadcast payload is over the project's size limit.",
        isRetryable: false)
    }
    return RealtimeError(kind: .server, message: reason)
  }

  /// The error for a WebSocket that closed while the engine still needed it.
  package static func socketClosed(code: WebSocketCloseCode?, reason: String?) -> RealtimeError {
    var message = "WebSocket closed"
    if let code { message += " (code \(code.rawValue))" }
    if let reason, !reason.isEmpty { message += ": \(reason)" }
    var error = RealtimeError(kind: .transport, message: message)
    error.closeCode = code
    return error
  }

  /// The error for an HTTP upgrade the server refused.
  ///
  /// 401, 403 and 404 mean the key, tenant or project is wrong and a retry cannot help. Every
  /// other status (429 and 5xx in practice) is transient.
  package static func upgradeFailed(status: Int, underlyingError: (any Error)? = nil)
    -> RealtimeError
  {
    RealtimeError(
      kind: .transport,
      message: "WebSocket upgrade failed with HTTP status \(status).",
      isRetryable: ![401, 403, 404].contains(status),
      underlyingError: underlyingError
    )
  }
}
