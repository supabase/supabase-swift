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
///   try await channel.subscribe()
/// } catch let error as RealtimeError where error.kind == .unauthorized {
///   signInAgain()
/// }
/// ```
public struct RealtimeError: SupabaseError {
  /// What failed. Compare against the static members and keep a fallback branch.
  public struct Kind: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    /// The kind's name, such as `"timeout"`.
    public let rawValue: String

    /// Creates a kind from its name.
    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    /// Creates a kind from a string literal.
    public init(stringLiteral value: String) {
      self.init(rawValue: value)
    }

    /// A subscribe, push, heartbeat or REST broadcast did not complete within the configured
    /// timeout. Retry, or raise ``RealtimeClientOptions/requestTimeout`` if it happens often.
    public static let timeout: Kind = "timeout"
    /// A send was attempted on a channel that is not subscribed. Call `subscribe()` first.
    public static let notSubscribed: Kind = "notSubscribed"
    /// The socket went away while a reply was pending: the client reconnects on its own, so retry
    /// the call once the status is back to connected. Also thrown, with
    /// ``RealtimeError/isRetryable`` `false`, when `subscribe()` found the client disconnected and
    /// `connectOnSubscribe` is off, or when `disconnect()` stopped a subscribe in flight. Call
    /// `connect()` before you subscribe again.
    public static let notConnected: Kind = "notConnected"
    /// `httpSend` needs an access token and none was available. Sign in, or pass an
    /// `accessToken` closure, before sending. No request was sent.
    public static let accessTokenMissing: Kind = "accessTokenMissing"
    /// The server rejected the token or the topic's RLS policy denied access. Retrying as-is
    /// will not help; ``RealtimeError/serverCode`` says which check failed.
    public static let unauthorized: Kind = "unauthorized"
    /// The server applied a rate limit. ``RealtimeError/serverCode`` names which one. A channel
    /// waits 30 s before it joins again.
    public static let rateLimited: Kind = "rateLimited"
    /// The server closed the channel (`phx_close`) with a `system` error. The message carries
    /// the server's reason.
    public static let channelClosed: Kind = "channelClosed"
    /// A broadcast with `ack` was rejected because the payload is over the project's limit.
    public static let payloadTooLarge: Kind = "payloadTooLarge"
    /// The server closed the channel while a subscribe was in flight.
    public static let channelClosedByServer: Kind = "channelClosedByServer"
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
    /// The code as the server sends it, such as `"Unauthorized"`.
    public let rawValue: String

    /// Creates a code from the value the server sends.
    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    /// Creates a code from a string literal.
    public init(stringLiteral value: String) {
      self.init(rawValue: value)
    }

    /// The join had no topic.
    public static let topicNameRequired: ServerCode = "TopicNameRequired"
    /// The server rejected the token, for example because it expired.
    public static let invalidJWTToken: ServerCode = "InvalidJWTToken"
    /// The token is not a well-formed JWT.
    public static let malformedJWT: ServerCode = "MalformedJWT"
    /// The server could not verify the token's signature.
    public static let jwtSignatureError: ServerCode = "JwtSignatureError"
    /// The server could not set up the signer to verify the token.
    public static let jwtSignerError: ServerCode = "JwtSignerError"
    /// A row level security policy on `realtime.messages` denied the join.
    public static let unauthorized: ServerCode = "Unauthorized"
    /// The project allows only private channels.
    public static let privateOnly: ServerCode = "PrivateOnly"
    /// The server does not know the project.
    public static let tenantNotFound: ServerCode = "TenantNotFound"
    /// Realtime is turned off for the project.
    public static let realtimeDisabledForTenant: ServerCode = "RealtimeDisabledForTenant"
    /// The server cannot serve the channel's configuration.
    public static let realtimeDisabledForConfiguration: ServerCode =
      "RealtimeDisabledForConfiguration"
    /// The server could not replay broadcast messages with the requested replay options.
    public static let unableToReplayMessages: ServerCode = "UnableToReplayMessages"
    /// The project has too many channels open.
    public static let channelRateLimitReached: ServerCode = "ChannelRateLimitReached"
    /// The project has too many clients connected.
    public static let connectionRateLimitReached: ServerCode = "ConnectionRateLimitReached"
    /// The project sent too many joins per second.
    public static let clientJoinRateLimitReached: ServerCode = "ClientJoinRateLimitReached"
    /// The Realtime server is restarting.
    public static let realtimeRestarting: ServerCode = "RealtimeRestarting"
    /// The server is still connecting to the project's database.
    public static let initializingProjectConnection: ServerCode = "InitializingProjectConnection"
    /// The server's connection pool to the project's database is full.
    public static let increaseConnectionPool: ServerCode = "IncreaseConnectionPool"
    /// The project's database has no free connections.
    public static let databaseLackOfConnections: ServerCode = "DatabaseLackOfConnections"
    /// The server tried to connect to the project's database too often.
    public static let databaseConnectionRateLimitReached: ServerCode =
      "DatabaseConnectionRateLimitReached"
    /// The server could not connect to the project's database.
    public static let unableToConnectToProject: ServerCode = "UnableToConnectToProject"
    /// The database canceled a query the server ran for the channel.
    public static let queryCanceled: ServerCode = "QueryCanceled"
    /// The database is missing the `realtime.messages` partition the server needs.
    public static let missingPartition: ServerCode = "MissingPartition"
    /// A call between Realtime server nodes timed out.
    public static let timeoutOnRpcCall: ServerCode = "TimeoutOnRpcCall"
    /// A call between Realtime server nodes failed.
    public static let errorOnRpcCall: ServerCode = "ErrorOnRpcCall"
    /// The server did not set up the channel's Postgres changes in time.
    public static let postgresChangesSubscribeTimeout: ServerCode =
      "PostgresChangesSubscribeTimeout"
    /// The server met an error it has no code for.
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
      .postgresChangesSubscribeTimeout,
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

  /// What failed. Check it first.
  public var kind: Kind
  /// A description of the failure, from the server or from the SDK.
  public var message: String
  /// The code parsed from a server error reason, when the reason carried one.
  public var serverCode: ServerCode?
  /// The close status, when a WebSocket close caused this error.
  package var closeCode: WebSocketCloseCode?
  /// Whether the same operation can succeed later without the caller changing anything.
  ///
  /// `false` for errors the user must act on: a rejected token, a denied policy, a refused
  /// upgrade with 401/403/404. The client stops reconnecting when it meets one.
  public var isRetryable: Bool
  /// The HTTP error response, for a ``Kind-swift.struct/server`` error from the REST broadcast
  /// endpoint that `httpSend` uses.
  public var response: HTTPErrorResponse?
  /// The error that caused this one, such as a `URLError` or a `DecodingError`.
  public var underlyingError: (any Error)?

  /// Creates an error.
  ///
  /// - Parameters:
  ///   - kind: What failed.
  ///   - message: A description of the failure.
  ///   - serverCode: The code from the server's error reason, if any.
  ///   - isRetryable: Whether the same call can succeed later without a change.
  ///   - response: The HTTP error response, if any.
  ///   - underlyingError: The error that caused this one, if any.
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

  /// The kind and the message, for logs.
  public var description: String {
    formattedDescription(kind: kind.rawValue)
  }
}

extension RealtimeError {
  /// The server closed the channel while a subscribe was in flight.
  public static let channelClosedByServer = RealtimeError(
    kind: .channelClosedByServer, message: "Channel was closed by the server while subscribing.")

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
  /// bare strings. It is retryable unless ``JoinRecovery`` says the join fails for good: an
  /// expired-token `InvalidJWTToken` is retryable because a fresh token can fix it.
  package static func joinError(reason: String) -> RealtimeError {
    let code = ServerCode.parse(reason)
    let recovery = JoinRecovery(serverCode: code, reason: reason)
    let kind: Kind
    switch (code, recovery) {
    case (.some(let code), _) where ServerCode.authentication.contains(code): kind = .unauthorized
    case (.some(let code), _) where ServerCode.rateLimit.contains(code): kind = .rateLimited
    // Without a code, the wording is all there is: an expired token or a revoked permission is
    // an auth failure, a rate limit is a rate limit.
    case (nil, .refreshToken), (nil, .fail): kind = .unauthorized
    case (nil, .backOff): kind = .rateLimited
    default: kind = .server
    }
    return RealtimeError(
      kind: kind, message: reason, serverCode: code, isRetryable: recovery != .fail)
  }

  /// The error for a `phx_reply` with `status: "error"` to a push sent with `ack`.
  ///
  /// The server answers a payload over the project's size limit with the bare string
  /// `"payload_size_exceeded"`; anything else is reported as it came, with the code in front
  /// of a `"<Code>: <message>"` reason in ``serverCode``.
  package static func ackError(reason: String) -> RealtimeError {
    if reason == "payload_size_exceeded" {
      return RealtimeError(
        kind: .payloadTooLarge, message: "Broadcast payload is over the project's size limit.",
        isRetryable: false)
    }
    return RealtimeError(kind: .server, message: reason, serverCode: ServerCode.parse(reason))
  }

  /// The error for a WebSocket that closed while the client still needed it.
  package static func socketClosed(code: WebSocketCloseCode?, reason: String?) -> RealtimeError {
    var message = "WebSocket closed"
    if let code { message += " (code \(code.rawValue))" }
    if let reason, !reason.isEmpty { message += ": \(reason)" }
    var error = RealtimeError(kind: .transport, message: message)
    error.closeCode = code
    return error
  }

  /// Whether `other` reports the same failure. `underlyingError` is not compared: it is
  /// rarely `Equatable`, and two errors with the same kind, message and codes mean the same.
  func isSameFailure(as other: RealtimeError?) -> Bool {
    guard let other else { return false }
    return kind == other.kind && message == other.message && serverCode == other.serverCode
      && closeCode == other.closeCode && isRetryable == other.isRetryable
  }

  /// The error for an HTTP upgrade the server refused.
  ///
  /// 401, 403 and 404 mean the key, tenant or project is wrong and a retry cannot help. Every
  /// other status (429 and 5xx in practice) is transient. A custom ``WebSocketTransport`` throws
  /// this error so the client knows whether to retry.
  ///
  /// - Parameters:
  ///   - status: The HTTP status the server answered the upgrade with.
  ///   - underlyingError: The transport's own error, if any.
  public static func upgradeFailed(status: Int, underlyingError: (any Error)? = nil)
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

extension RealtimeError {
  /// What a channel does after a join fails with this error.
  enum JoinRecovery: Hashable {
    /// The caller must act: `subscribe()` throws.
    case fail
    /// A fresh token can fix it: rejoin at once, one time.
    case refreshToken
    /// The server applied a rate limit: wait the long interval, then rejoin.
    case backOff
    /// Rejoin after the next step of the rejoin backoff.
    case retry

    /// A server code decides when the reason has one. The server sends a few reasons without a
    /// code; those fall back to their wording.
    init(serverCode: ServerCode?, reason: String) {
      if let code = serverCode {
        if code == .invalidJWTToken, reason.contains("expired") {
          self = .refreshToken
        } else if ServerCode.fatal.contains(code) {
          self = .fail
        } else if ServerCode.rateLimit.contains(code) {
          self = .backOff
        } else {
          self = .retry
        }
      } else if reason.contains("Token has expired") {
        self = .refreshToken
      } else if reason.contains("Too many") && reason.contains("per second")
        || reason.contains("rate limit")
      {
        self = .backOff
      } else if reason.contains("You no longer have permission") {
        self = .fail
      } else {
        self = .retry
      }
    }
  }

  /// How a channel recovers from this error when a join attempt fails with it.
  var joinRecovery: JoinRecovery {
    isRetryable ? JoinRecovery(serverCode: serverCode, reason: message) : .fail
  }
}
