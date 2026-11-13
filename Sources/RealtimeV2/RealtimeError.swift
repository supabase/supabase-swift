//
//  RealtimeError.swift
//
//
//  Created by Guilherme Souza on 30/10/23.
//

public import Foundation

/// An error thrown by the Realtime client and channels.
///
/// Check ``kind`` to learn what failed. ``underlyingError`` carries the cause when there is one.
///
/// ```swift
/// do {
///   try await channel.subscribeWithError()
/// } catch let error as RealtimeError where error.kind == .timeout {
///   retryLater()
/// }
/// ```
///
/// > Note: Supabase Swift v3 also conforms this type to `SupabaseError` and adds an HTTP
/// > `response`. This version has neither.
public struct RealtimeError: LocalizedError, CustomStringConvertible {
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

    /// A subscribe did not complete in time, or used all of its retry attempts.
    ///
    /// This version of the SDK does not throw it for a REST broadcast that times out: `httpSend`
    /// throws the SDK's own timeout error, which is not a ``RealtimeError``. A heartbeat that
    /// times out is not thrown to the caller; read ``RealtimeClientV2/heartbeats()``.
    public static let timeout: Kind = "timeout"

    /// A send was attempted on a channel that is not subscribed.
    ///
    /// This version of the SDK does not throw it: a push on an unsubscribed channel reports an
    /// issue or falls back to REST.
    public static let notSubscribed: Kind = "notSubscribed"

    /// The socket went away while a reply was pending, or the client is not connected.
    ///
    /// This version of the SDK does not throw it.
    public static let notConnected: Kind = "notConnected"

    /// The `accessToken` closure threw when `httpSend` asked it for a token.
    ///
    /// This version of the SDK does not throw it.
    public static let accessToken: Kind = "accessToken"

    /// The server rejected the token or a policy denied access.
    ///
    /// This version of the SDK does not throw it.
    public static let unauthorized: Kind = "unauthorized"

    /// The server applied a rate limit.
    ///
    /// This version of the SDK does not throw it.
    public static let rateLimited: Kind = "rateLimited"

    /// The server closed the channel with a `system` error.
    ///
    /// This version of the SDK does not throw it.
    public static let channelClosed: Kind = "channelClosed"

    /// A broadcast was rejected because the payload is over the project's limit.
    ///
    /// This version of the SDK does not throw it.
    public static let payloadTooLarge: Kind = "payloadTooLarge"

    /// The server closed the channel while a subscribe was in flight.
    public static let channelClosedByServer: Kind = "channelClosedByServer"

    /// The server reported an error on the channel (`phx_error`).
    ///
    /// This version of the SDK does not throw it.
    public static let channelError: Kind = "channelError"

    /// The call used a channel that was removed from the client.
    ///
    /// This version of the SDK does not throw it.
    public static let channelRemoved: Kind = "channelRemoved"

    /// The server answered a REST broadcast with an error. Read ``RealtimeError/message``.
    public static let server: Kind = "server"

    /// The network path failed.
    ///
    /// This version of the SDK does not throw it: network errors propagate as themselves.
    public static let transport: Kind = "transport"

    /// A frame from the server could not be decoded, or a value did not decode as the type you
    /// asked for.
    public static let decoding: Kind = "decoding"

    /// The client refused its configuration.
    ///
    /// This version of the SDK does not throw it.
    public static let invalidConfiguration: Kind = "invalidConfiguration"

    /// The SDK refused to send: a payload did not encode, or `httpSend` had no access token.
    /// Nothing was sent.
    public static let invalidRequest: Kind = "invalidRequest"
  }

  /// The code the server prefixes to a join or channel error reason, as in
  /// `"Unauthorized: You do not have permissions…"`.
  ///
  /// The server owns this set and adds to it without notice, so compare against the static
  /// members and keep a fallback branch.
  public struct Code: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
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
    public static let topicNameRequired: Code = "TopicNameRequired"
    /// The server rejected the token, for example because it expired.
    public static let invalidJWTToken: Code = "InvalidJWTToken"
    /// The token is not a well-formed JWT.
    public static let malformedJWT: Code = "MalformedJWT"
    /// The server could not verify the token's signature.
    public static let jwtSignatureError: Code = "JwtSignatureError"
    /// The server could not set up the signer to verify the token.
    public static let jwtSignerError: Code = "JwtSignerError"
    /// A row level security policy on `realtime.messages` denied the join.
    public static let unauthorized: Code = "Unauthorized"
    /// The project allows only private channels.
    public static let privateOnly: Code = "PrivateOnly"
    /// The server does not know the project.
    public static let tenantNotFound: Code = "TenantNotFound"
    /// Realtime is turned off for the project.
    public static let realtimeDisabledForTenant: Code = "RealtimeDisabledForTenant"
    /// The server cannot serve the channel's configuration.
    public static let realtimeDisabledForConfiguration: Code =
      "RealtimeDisabledForConfiguration"
    /// The server could not replay broadcast messages with the requested replay options.
    public static let unableToReplayMessages: Code = "UnableToReplayMessages"
    /// The project has too many channels open.
    public static let channelRateLimitReached: Code = "ChannelRateLimitReached"
    /// The project has too many clients connected.
    public static let connectionRateLimitReached: Code = "ConnectionRateLimitReached"
    /// The project sent too many joins per second.
    public static let clientJoinRateLimitReached: Code = "ClientJoinRateLimitReached"
    /// The Realtime server is restarting.
    public static let realtimeRestarting: Code = "RealtimeRestarting"
    /// The server is still connecting to the project's database.
    public static let initializingProjectConnection: Code = "InitializingProjectConnection"
    /// The server's connection pool to the project's database is full.
    public static let increaseConnectionPool: Code = "IncreaseConnectionPool"
    /// The project's database has no free connections.
    public static let databaseLackOfConnections: Code = "DatabaseLackOfConnections"
    /// The server tried to connect to the project's database too often.
    public static let databaseConnectionRateLimitReached: Code =
      "DatabaseConnectionRateLimitReached"
    /// The server could not connect to the project's database.
    public static let unableToConnectToProject: Code = "UnableToConnectToProject"
    /// The database canceled a query the server ran for the channel.
    public static let queryCanceled: Code = "QueryCanceled"
    /// The database is missing the `realtime.messages` partition the server needs.
    public static let missingPartition: Code = "MissingPartition"
    /// A call between Realtime server nodes timed out.
    public static let timeoutOnRpcCall: Code = "TimeoutOnRpcCall"
    /// A call between Realtime server nodes failed.
    public static let errorOnRpcCall: Code = "ErrorOnRpcCall"
    /// The server did not set up the channel's Postgres changes in time.
    public static let postgresChangesSubscribeTimeout: Code =
      "PostgresChangesSubscribeTimeout"
    /// The server met an error it has no code for.
    public static let unknownErrorOnChannel: Code = "UnknownErrorOnChannel"
  }

  /// What failed. Check it first.
  public var kind: Kind

  /// A description of the failure, from the server or from the SDK.
  public var message: String

  /// The code the server put in front of a join or channel error reason.
  ///
  /// This version of the SDK never sets it: a failed subscribe does not carry the server's
  /// reason. It is here so that code written for v3 compiles.
  public var code: Code?

  /// The error that caused this one, such as an `EncodingError` or a `DecodingError`.
  public var underlyingError: (any Error)?

  /// The same text as ``message``.
  public var errorDescription: String? { message }

  /// The kind and the message, plus the code when the message does not start with it, for logs.
  public var description: String {
    var description = "RealtimeError(\(kind.rawValue)"
    if let code, !message.hasPrefix("\(code.rawValue): ") {
      description += ", code: \(code.rawValue)"
    }
    return description + "): \(message)"
  }

  /// Creates an error.
  ///
  /// - Parameters:
  ///   - kind: What failed.
  ///   - message: A description of the failure.
  ///   - code: The code from the server's error reason, if any.
  ///   - underlyingError: The error that caused this one, if any.
  public init(
    kind: Kind,
    message: String,
    code: Code? = nil,
    underlyingError: (any Error)? = nil
  ) {
    self.kind = kind
    self.message = message
    self.code = code
    self.underlyingError = underlyingError
  }

  /// Creates an error of kind ``Kind-swift.struct/server`` from a server reason.
  package init(_ errorDescription: String) {
    self.init(kind: .server, message: errorDescription)
  }
}

extension RealtimeError {
  /// A subscribe used all of its retry attempts.
  ///
  /// v3 has no retry limit and no kind for it. The attempts fail on a join timeout or on a socket
  /// that is not connected, so ``Kind-swift.struct/timeout`` is the closest kind.
  static var maxRetryAttemptsReached: Self {
    Self(kind: .timeout, message: "Maximum retry attempts reached.")
  }

  /// The server closed the channel while a subscribe was in flight.
  public static var channelClosedByServer: Self {
    Self(
      kind: .channelClosedByServer, message: "Channel was closed by the server while subscribing.")
  }

  /// The server answered the WebSocket upgrade with an HTTP status instead of opening the socket.
  ///
  /// A custom ``WebSocketTransport`` throws this error from `connect`. The kind follows the
  /// status: 401 and 403 are ``Kind-swift.struct/unauthorized``, 429 is
  /// ``Kind-swift.struct/rateLimited``, and every other status is ``Kind-swift.struct/server``.
  ///
  /// > Note: In v3 the client stops on 401, 403 and 404 and tries the other statuses again. On
  /// > this version the client does not read the status: every failed connect follows the same
  /// > reconnect rules.
  ///
  /// - Parameters:
  ///   - status: The HTTP status the server answered the upgrade with.
  ///   - underlyingError: The transport's own error, if any.
  public static func upgradeFailed(status: Int, underlyingError: (any Error)? = nil)
    -> RealtimeError
  {
    let kind: Kind =
      switch status {
      case 401, 403: .unauthorized
      case 429: .rateLimited
      default: .server
      }
    return RealtimeError(
      kind: kind,
      message: "WebSocket upgrade failed with HTTP status \(status).",
      underlyingError: underlyingError
    )
  }

  static var heartbeatTimeout: Self {
    Self(kind: .timeout, message: "heartbeat timeout")
  }

  static func decoding(_ message: String, underlyingError: (any Error)? = nil) -> Self {
    Self(kind: .decoding, message: message, underlyingError: underlyingError)
  }

  static func invalidRequest(_ message: String, underlyingError: (any Error)? = nil) -> Self {
    Self(kind: .invalidRequest, message: message, underlyingError: underlyingError)
  }
}

extension RealtimeError.Kind {
  /// Matches a ``RealtimeError`` of this ``RealtimeError/kind``, so a `catch` clause can name the
  /// kind directly.
  ///
  /// ```swift
  /// do {
  ///   try await channel.subscribeWithError()
  /// } catch RealtimeError.Kind.timeout {
  ///   retryLater()
  /// }
  /// ```
  @_disfavoredOverload
  public static func ~= (kind: RealtimeError.Kind, error: any Error) -> Bool {
    (error as? RealtimeError)?.kind == kind
  }
}

extension RealtimeError.Code {
  /// Matches a ``RealtimeError`` with this ``RealtimeError/code``, so a `catch` clause can name
  /// the code directly.
  ///
  /// ```swift
  /// do {
  ///   try await channel.subscribeWithError()
  /// } catch RealtimeError.Code.privateOnly {
  ///   usePrivateChannel()
  /// }
  /// ```
  @_disfavoredOverload
  public static func ~= (code: RealtimeError.Code, error: any Error) -> Bool {
    (error as? RealtimeError)?.code == code
  }
}
