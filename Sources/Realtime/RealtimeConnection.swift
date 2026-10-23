//
//  RealtimeConnection.swift
//  Realtime
//
//  Created by Guilherme Souza on 23/10/26.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
import Helpers
import Logging
import Phoenix

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Channels hold this, not the client, so no reference cycle exists between them.
final class RealtimeConnection: Sendable {
  let socket: Socket
  let options: RealtimeClientOptions
  let url: URL
  let http: HTTPClient
  /// The newest token from any source. Joins send it.
  let token: LockIsolated<String?>
  /// The token ``RealtimeClient/setAuth(_:)`` last sent to the subscribed channels.
  let pushedToken: LockIsolated<String?>

  init(url: URL, options: RealtimeClientOptions, transport: any Transport) {
    var withClientInfo = options
    if withClientInfo.headers[.xClientInfo] == nil {
      withClientInfo.headers[.xClientInfo] = "realtime-swift/\(version)"
    }
    let options = withClientInfo
    let params = [
      "apikey": options.apikey, "log_level": options.logLevel?.rawValue,
    ].compactMapValues { $0 }
    self.url = url
    self.options = options
    http = HTTPClient(
      configuration: options.http, appending: [LoggerInterceptor(logger: options.logger)])
    let initialToken = options.headers[.authorization]?.split(separator: " ").last.map(String.init)
    let token = LockIsolated(initialToken)
    self.token = token
    pushedToken = LockIsolated(initialToken)
    let accessToken = options.accessToken

    let maxAttempts = options.maxRetryAttempts
    let reconnectDelay = options.reconnectDelay
    let logger = options.logger
    socket = Socket(
      endpoint: url,
      options: SocketOptions(
        params: {
          await Self.refresh(token, from: accessToken)
          return params
        },
        heartbeatInterval: options.heartbeatInterval,
        reconnect: { failure, attempt in
          reconnectDecision(
            httpStatus: failure.httpStatus, closeCode: failure.closeCode, attempt: attempt,
            maxAttempts: maxAttempts, base: reconnectDelay)
        },
        timeout: options.timeout,
        codec: SupabaseFrameCodec(),
        log: { level, text in
          let text = redactingURLQueries(text)
          switch level {
          case .error: logger.error("\(text)")
          default: logger.debug("\(text)")
          }
        }
      ),
      transport: transport,
      clock: options.clock
    )
  }

  /// A join attempt waits at least ``RealtimeClientOptions/defaultTimeout`` for its reply. The
  /// server can hold a join, such as a private channel rejection, longer than a short `timeout`,
  /// and Phoenix drops the reply of an attempt that already timed out.
  var joinTimeout: Duration {
    max(options.timeout, RealtimeClientOptions.defaultTimeout)
  }

  func connect() async throws {
    await socket.connect()
    for await status in socket.statuses {
      switch status {
      case .connected: return
      case .disconnected(let failure?): throw RealtimeError(stoppedOn: failure)
      case .disconnected(nil): throw RealtimeError.notConnected
      case .connecting, .waitingToReconnect: continue
      }
    }
    throw CancellationError()
  }

  /// Throws when the reconnect policy stops the socket, or when ``RealtimeClient/disconnect(code:reason:)``
  /// closes it.
  ///
  /// - Parameter didConnect: `false` when the caller did not connect first, so a socket that
  ///   was never connected is waited for.
  func failWhenSocketStops(didConnect: Bool) async throws {
    var wasActive = didConnect
    for await status in socket.statuses {
      switch status {
      case .disconnected(let failure?): throw RealtimeError(stoppedOn: failure)
      case .disconnected(nil): if wasActive { throw RealtimeError.notConnected }
      case .connecting, .connected, .waitingToReconnect: wasActive = true
      }
    }
    throw CancellationError()
  }

  /// Asks `RealtimeClientOptions.accessToken` for a new token. The socket also does this before
  /// each connection attempt, so the joins that follow a reconnect send a current token.
  @discardableResult
  func refreshToken() async -> String? {
    await Self.refresh(token, from: options.accessToken)
  }

  @discardableResult
  private static func refresh(
    _ token: LockIsolated<String?>, from accessToken: (@Sendable () async throws -> String?)?
  ) async -> String? {
    if let fresh = try? await accessToken?() {
      token.setValue(fresh)
      return fresh
    }
    return token.value
  }

  func broadcastURL(topic: String, event: String, isPrivate: Bool) -> URL {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return url
    }
    let encodedTopic =
      topic.addingPercentEncoding(withAllowedCharacters: .sbURLPathComponentAllowed) ?? topic
    let encodedEvent =
      event.addingPercentEncoding(withAllowedCharacters: .sbURLPathComponentAllowed) ?? event
    var path = components.percentEncodedPath
    if path.hasSuffix("/") { path.removeLast() }
    path += "/api/broadcast/\(encodedTopic)/events/\(encodedEvent)"
    components.percentEncodedPath = path
    if isPrivate {
      components.queryItems = [URLQueryItem(name: "private", value: "true")]
    }
    return components.url ?? url
  }
}

extension CharacterSet {
  /// RFC 3986 unreserved characters.
  static let sbURLPathComponentAllowed: CharacterSet = {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return allowed
  }()
}

extension AsyncStream where Element: Sendable {
  func forwarding<T: Sendable & Equatable>(
    removingDuplicates: Bool, _ transform: @escaping @Sendable (Element) -> T
  ) -> AsyncStream<T> {
    let (stream, continuation) = AsyncStream<T>.makeStream()
    let task = Task {
      var last: T?
      for await element in self {
        let value = transform(element)
        if removingDuplicates, value == last { continue }
        last = value
        continuation.yield(value)
      }
      continuation.finish()
    }
    continuation.onTermination = { _ in task.cancel() }
    return stream
  }
}
