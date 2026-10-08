//
//  RealtimeChannel.swift
//  Realtime
//
//  Created by Guilherme Souza on 08/10/26.
//

import ConcurrencyExtras
public import Foundation
import HTTPTypes
package import Helpers
import Logging

/// What a channel needs to send broadcasts over REST.
package struct RealtimeREST: Sendable {
  /// The Realtime HTTP endpoint, such as `https://<project>.supabase.co/realtime/v1`.
  package var baseURL: URL
  package var apikey: String?
  package var http: HTTPClientConfiguration
  /// How long a REST broadcast waits when the call does not pass its own timeout.
  package var timeout: Duration
  package var clock: any Clock<Duration>
  package var accessToken: @Sendable () async -> String?

  package init(
    baseURL: URL, apikey: String?, http: HTTPClientConfiguration, timeout: Duration,
    clock: any Clock<Duration>, accessToken: @escaping @Sendable () async -> String?
  ) {
    self.baseURL = baseURL
    self.apikey = apikey
    self.http = http
    self.timeout = timeout
    self.clock = clock
    self.accessToken = accessToken
  }
}

/// One topic on the Realtime socket: broadcast, postgres changes and its subscription status.
///
/// Every stream-returning method registers its listener before it returns, so a stream made
/// before ``subscribe()`` sees everything from the join on. Elements are buffered without a limit;
/// a consumer that stops iterating without ending its loop holds every later element in memory.
public final class RealtimeChannel: Sendable {
  /// The channel name. The SDK adds the `realtime:` prefix on the wire.
  public let topic: String
  /// The options the channel joins with.
  public let configuration: RealtimeChannelConfiguration

  let wireTopic: String
  let engine: RealtimeEngine
  private let rest: RealtimeREST
  private let http: HTTPClient
  /// The postgres bindings, in the order the streams asked for them. The server's ids for them
  /// come back in the same order.
  private let bindings = LockIsolated<[PostgresJoinConfig]>([])
  /// Set once a presence stream exists, so every join asks the server for presence.
  private let wantsPresence = LockIsolated(false)

  package init(
    topic: String, configuration: RealtimeChannelConfiguration, engine: RealtimeEngine,
    rest: RealtimeREST
  ) {
    self.topic = topic
    self.configuration = configuration
    self.wireTopic = "realtime:\(topic)"
    self.engine = engine
    self.rest = rest
    self.http = HTTPClient(configuration: rest.http, appending: [])
  }

  // MARK: - Status

  /// The subscription status, read without waiting.
  public var status: RealtimeChannelStatus {
    engine.mirror.channel(wireTopic)
  }

  /// The subscription status, starting with the current one. Only the newest status is buffered.
  public var statusChanges: RealtimeStream<RealtimeChannelStatus> {
    RealtimeStream(engine.mirror.channelStatuses(wireTopic))
  }

  /// Rejoins and `system` messages from the server.
  public var events: RealtimeStream<RealtimeChannelEvent> {
    RealtimeStream(engine.inbound(wireTopic), transform: RealtimeChannelEvent.init)
  }

  // MARK: - Lifecycle

  /// Joins the channel, connecting the socket first when needed.
  ///
  /// When the channel has postgres changes streams, it also waits until the server has attached
  /// them, so a change made after this returns is delivered. With
  /// ``RealtimeChannelConfiguration/PostgresChanges/waitForSubscription`` the server holds the
  /// join reply until then; otherwise the channel waits up to
  /// ``RealtimeChannelConfiguration/PostgresChanges/subscriptionTimeout`` for the server's
  /// "Subscribed to PostgreSQL" message.
  ///
  /// - Throws: ``RealtimeError`` with the server's reason when it refuses the join for good,
  ///   ``RealtimeError/Kind/notSubscribed`` when ``unsubscribe()`` runs first, and
  ///   ``RealtimeError/Kind/server`` or ``RealtimeError/Kind/timeout`` when the postgres changes
  ///   bindings fail to attach. In the last two cases the channel stays joined, and the server may
  ///   still attach them later.
  ///
  /// Calling it on a channel that is already subscribed returns at once, without waiting for the
  /// postgres changes bindings. A ``postgresChanges(event:schema:table:filter:select:)`` stream
  /// made while this call is joining makes the channel join again, and this call returns once that
  /// binding is live too. A stream made after it returned also makes the channel join again;
  /// ``RealtimeChannelEvent/resubscribed`` on ``events`` marks when that binding is live.
  public func subscribe() async throws {
    if status.isSubscribed { return }
    let inbound = engine.inbound(wireTopic)
    var config = RealtimeJoinConfig(configuration, bindings: bindings.value)
    config.presence.enabled = wantsPresence.value
    await engine.addChannel(wireTopic, config: config)
    try await engine.subscribe(wireTopic)
    // A stream made while the join was in flight may have missed both the join and its own
    // update, since the status still read as unsubscribed.
    await engine.updateBindings(wireTopic, bindings.value)
    if wantsPresence.value { await engine.enablePresence(wireTopic) }
    guard !bindings.value.isEmpty, !configuration.postgresChanges.waitForSubscription else {
      return
    }
    try await awaitPostgresChanges(inbound)
  }

  /// Leaves the channel. Returns once the server confirmed, the leave timed out, or the socket
  /// was already gone.
  public func unsubscribe() async {
    await engine.unsubscribe(wireTopic)
  }

  private func awaitPostgresChanges(_ inbound: AsyncStream<ChannelInbound>) async throws {
    let timeout = configuration.postgresChanges.subscriptionTimeout
    let failure: String?
    do {
      failure = try await withTimeout(timeout, clock: engine.clock) { [topic] in
        for await element in inbound {
          switch RealtimeChannelEvent(element) {
          case .postgresChangesReady?: return nil
          case .postgresChangesFailed(let message)?: return message
          default: continue
          }
        }
        // Cancelling `subscribe()` also ends this loop; report that as cancellation.
        try Task.checkCancellation()
        throw RealtimeError(
          kind: .notSubscribed, message: "channel \(topic) ended before postgres changes were ready"
        )
      }
    } catch is TimeoutError {
      throw RealtimeError(
        kind: .timeout, message: "postgres changes were not ready within \(timeout)")
    }
    if let failure {
      throw RealtimeError(kind: .server, message: failure)
    }
  }

  // MARK: - Presence

  /// Who is on the channel, and this client's own presence entry.
  public var presence: RealtimePresence {
    RealtimePresence(channel: self)
  }

  /// Makes every later join enable presence. On a channel that is joined or joining without it,
  /// the channel joins again.
  func enablePresence() {
    let alreadyWanted = wantsPresence.withValue { wanted in
      defer { wanted = true }
      return wanted
    }
    guard !alreadyWanted else { return }
    switch status {
    case .unsubscribed:
      break
    case .subscribing, .subscribed, .resubscribing, .unsubscribing, .failed:
      Task { [engine, wireTopic] in await engine.enablePresence(wireTopic) }
    }
  }

  // MARK: - Broadcast

  /// Broadcast messages whose event is exactly `event`.
  public func broadcasts(event: String) -> RealtimeStream<BroadcastMessage> {
    RealtimeStream(engine.inbound(wireTopic)) { inbound in
      BroadcastMessage(inbound).flatMap { $0.event == event ? $0 : nil }
    }
  }

  /// Sends `payload` as JSON to everyone on the channel.
  ///
  /// With ``RealtimeChannelConfiguration/Broadcast/acknowledge`` it returns once the server
  /// acknowledged the message. On a private channel, a timeout then means row level security
  /// denied the write or the database failed, because the server sends no reply in either case.
  ///
  /// - Throws: ``RealtimeError`` of kind ``RealtimeError/Kind/notSubscribed`` when the channel is
  ///   not joined, ``RealtimeError/Kind/timeout`` when an acknowledgement does not arrive, and
  ///   ``RealtimeError/Kind/payloadTooLarge`` when the message is over the project's size limit.
  public func broadcast(
    event: String, payload: some Encodable, encoder: JSONEncoder = .supabase()
  ) async throws {
    let value: JSONValue
    do {
      value = try JSONValue(payload, encoder: encoder)
    } catch {
      throw RealtimeError(
        kind: .encoding, message: "broadcast \(event) payload did not encode",
        underlyingError: error)
    }
    try await engine.send(
      wireTopic, event: "broadcast",
      payload: ["type": "broadcast", "event": .string(event), "payload": value],
      awaitReply: configuration.broadcast.acknowledge)
  }

  /// Sends `data` as a binary broadcast to everyone on the channel.
  ///
  /// - Throws: The same errors as ``broadcast(event:payload:encoder:)``.
  public func broadcast(event: String, data: Data) async throws {
    try await engine.sendBroadcast(
      wireTopic, event: event, data: data, awaitReply: configuration.broadcast.acknowledge)
  }

  /// Sends `payload` as JSON through the REST broadcast endpoint. The channel does not need to be
  /// joined.
  ///
  /// > Important: Requires Realtime server 2.97.0 or later.
  ///
  /// - Parameters:
  ///   - event: The broadcast event name.
  ///   - payload: The message, encoded with `JSONEncoder.supabase()`.
  ///   - timeout: How long to wait for the response, or `nil` for the client's timeout.
  /// - Throws: ``RealtimeError`` of kind ``RealtimeError/Kind/accessTokenMissing``,
  ///   ``RealtimeError/Kind/server``, ``RealtimeError/Kind/transport`` or
  ///   ``RealtimeError/Kind/timeout``.
  public func httpSend(event: String, payload: some Encodable, timeout: Duration? = nil)
    async throws
  {
    let body: Data
    do {
      body = try JSONEncoder.supabase().encode(payload)
    } catch {
      throw RealtimeError(
        kind: .encoding, message: "httpSend \(event) payload did not encode",
        underlyingError: error)
    }
    try await httpSend(event: event, body: body, contentType: "application/json", timeout: timeout)
  }

  /// Sends `data` as is, with an `application/octet-stream` content type, through the REST
  /// broadcast endpoint. The channel does not need to be joined.
  ///
  /// > Important: Requires Realtime server 2.97.0 or later.
  ///
  /// - Parameters:
  ///   - event: The broadcast event name.
  ///   - data: The request body.
  ///   - timeout: How long to wait for the response, or `nil` for the client's timeout.
  /// - Throws: The same errors as ``httpSend(event:payload:timeout:)``.
  public func httpSend(event: String, data: Data, timeout: Duration? = nil) async throws {
    try await httpSend(
      event: event, body: data, contentType: "application/octet-stream", timeout: timeout)
  }

  private func httpSend(event: String, body: Data, contentType: String, timeout: Duration?)
    async throws
  {
    guard let accessToken = await rest.accessToken() else {
      throw RealtimeError.accessTokenMissing
    }
    var headers: HTTPFields = [.contentType: contentType]
    if let apikey = rest.apikey {
      headers[.apikey] = apikey
    }
    headers[.authorization] = "Bearer \(accessToken)"
    let request = HTTPRequest(
      method: .post,
      url: RealtimeURL.broadcast(
        baseURL: rest.baseURL, topic: topic, event: event, isPrivate: configuration.isPrivate),
      headerFields: headers)

    let response: HTTPResponse
    let data: Data
    do {
      (response, data) = try await withTimeout(timeout ?? rest.timeout, clock: rest.clock) {
        [http] in try await http.send(request, body: body)
      }
    } catch is TimeoutError {
      throw RealtimeError(kind: .timeout, message: "httpSend() timed out.")
    } catch {
      // Only the network layer's own failures are relabelled. `CancellationError` and errors
      // thrown by a custom `ClientTransport` propagate as themselves.
      guard let urlError = error as? URLError else { throw error }
      // `URLSession` reports a cancelled `Task` as `URLError(.cancelled)`. A `.cancelled` with no
      // task cancellation behind it (a middleware cancelled the request) stays a transport error.
      if urlError.code == .cancelled, Task.isCancelled { throw CancellationError() }
      throw RealtimeError(
        kind: .transport, message: urlError.localizedDescription, underlyingError: urlError)
    }

    try Self.validateHTTPSendResponse(response, data: data)
  }

  private static func validateHTTPSendResponse(_ response: HTTPResponse, data: Data) throws {
    guard response.status.code == 202 else {
      var errorMessage = "Status Code: \(response.status.code)"
      if let errorBody = try? data.decoded(as: [String: String].self) {
        errorMessage = errorBody["error"] ?? errorBody["message"] ?? errorMessage
      }
      throw RealtimeError(
        kind: .server, message: errorMessage, response: HTTPErrorResponse(response, body: data))
    }
  }

  // MARK: - Postgres changes

  /// Row changes the server reads from the Postgres write-ahead log.
  ///
  /// Each call adds a binding to the channel. On a joined channel the SDK joins again to add it
  /// and reports ``RealtimeChannelEvent/resubscribed`` on ``events``.
  ///
  /// - Parameters:
  ///   - event: The statements to receive.
  ///   - schema: The schema of the table.
  ///   - table: The table, or `nil` for every table in `schema`.
  ///   - filter: A filter the server applies to each row.
  ///   - select: The columns to receive, or `nil` for every column.
  public func postgresChanges(
    event: PostgresChangeEvent = .all,
    schema: String = "public",
    table: String? = nil,
    filter: RealtimePostgresFilter? = nil,
    select: [String]? = nil
  ) -> RealtimeStream<PostgresChange> {
    postgresChanges(
      PostgresJoinConfig(
        event: event, schema: schema, table: table, filter: filter?.value, select: select)
    ) { $0 }
  }

  /// Row changes of `table`, bound to `Row`. Call ``TypedPostgresChange/row()`` on each element to
  /// decode its record; a row that does not decode throws there and the stream goes on.
  ///
  /// - Parameters:
  ///   - event: The statements to receive.
  ///   - schema: The schema of the table.
  ///   - table: The table.
  ///   - filter: A filter the server applies to each row.
  ///   - decoder: The decoder ``TypedPostgresChange/row()`` uses.
  public func postgresChanges<Row: Decodable>(
    of _: Row.Type,
    event: PostgresChangeEvent = .all,
    schema: String = "public",
    table: String,
    filter: RealtimePostgresFilter? = nil,
    decoder: JSONDecoder = .supabase()
  ) -> RealtimeStream<TypedPostgresChange<Row>> {
    postgresChanges(
      PostgresJoinConfig(event: event, schema: schema, table: table, filter: filter?.value),
      transform: TypedPostgresChange<Row>.wrapping(decoder: decoder))
  }

  private func postgresChanges<Element: Sendable>(
    _ binding: PostgresJoinConfig,
    transform: @escaping @Sendable (PostgresChange) -> Element
  ) -> RealtimeStream<Element> {
    let inbound = engine.inbound(wireTopic)
    let (index, all) = bindings.withValue {
      $0.append(binding)
      return ($0.count - 1, $0)
    }
    switch status {
    case .unsubscribed:
      break
    case .subscribing, .subscribed, .resubscribing, .unsubscribing, .failed:
      Task { [engine, wireTopic] in await engine.updateBindings(wireTopic, all) }
    }
    return RealtimeStream(inbound) { [engine, wireTopic, logger = engine.logger] inbound in
      guard case .message(let message) = inbound, message.event == "postgres_changes",
        let ids = message.payload["ids"]?.arrayValue?.compactMap(\.intValue)
      else { return nil }
      let serverIDs = engine.mirror.postgresChangeIDs(wireTopic)
      guard index < serverIDs.count, ids.contains(serverIDs[index]) else { return nil }
      let data = message.payload["data"]?.objectValue ?? [:]
      do {
        return transform(try PostgresChange(payload: data))
      } catch {
        logger.warning("dropping undecodable postgres change: \(error); payload: \(data)")
        return nil
      }
    }
  }
}

extension HTTPField.Name {
  static let apikey = HTTPField.Name("apikey")!
}
