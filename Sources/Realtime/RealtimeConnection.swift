//
//  RealtimeConnection.swift
//  Realtime
//
//  Created by Guilherme Souza on 23/10/26.
//

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
  let tokens: TokenBox

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
    // The socket's `timeout` bounds the token wait and the handshake together, so the wait takes
    // only half of it.
    let tokens = TokenBox(
      token: options.headers[.authorization]?.split(separator: " ").last.map(String.init),
      provider: options.accessToken,
      callTimeout: options.timeout / 2,
      clock: options.clock,
      logger: options.logger
    )
    self.tokens = tokens

    let reconnectDelay = options.reconnectDelay
    let logger = options.logger
    socket = Socket(
      endpoint: url,
      options: SocketOptions(
        params: {
          await tokens.refreshUnlessRecent()
          return params
        },
        heartbeatInterval: options.heartbeatInterval,
        reconnect: { failure, attempt in
          reconnectDecision(
            httpStatus: failure.httpStatus, closeCode: failure.closeCode, attempt: attempt,
            base: reconnectDelay)
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
  /// A socket that is disconnected when this starts is waited for, because the caller may be
  /// connecting it.
  ///
  /// - Parameters:
  ///   - statuses: A `socket.statuses` stream taken before the caller started connecting.
  ///   - isConnecting: `true` when the caller connects the socket meanwhile, so the stop that
  ///     the socket showed before, if any, is not this attempt's.
  func failWhenSocketStops(_ statuses: AsyncStream<SocketStatus>, isConnecting: Bool)
    async throws
  {
    var wasActive = false
    var isCurrent = true
    for await status in statuses {
      defer { isCurrent = false }
      if isCurrent, isConnecting {
        if case .disconnected = status { continue }
      }
      switch status {
      case .disconnected(let failure?): throw RealtimeError(stoppedOn: failure)
      case .disconnected(nil): if wasActive { throw RealtimeError.notConnected }
      case .connecting, .connected, .waitingToReconnect: wasActive = true
      }
    }
    throw CancellationError()
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
