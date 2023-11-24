// Copyright (c) 2021 David Stump <david@davidstump.net>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import Foundation
import Swift
@_spi(Internal) import _Helpers
import ConcurrencyExtras

/// Container class of bindings to the channel
struct Binding: Sendable {
  let type: String
  let filter: [String: String]

  // The callback to be triggered
  let callback: @Sendable (Message) -> Void

  let id: String?
}

public struct ChannelFilter {
  public let event: String?
  public let schema: String?
  public let table: String?
  public let filter: String?

  public init(
    event: String? = nil, schema: String? = nil, table: String? = nil, filter: String? = nil
  ) {
    self.event = event
    self.schema = schema
    self.table = table
    self.filter = filter
  }

  var asDictionary: [String: String] {
    [
      "event": event,
      "schema": schema,
      "table": table,
      "filter": filter,
    ].compactMapValues { $0 }
  }
}

public enum ChannelResponse {
  case ok, timedOut, error
}

public enum RealtimeListenTypes: String {
  case postgresChanges = "postgres_changes"
  case broadcast
  case presence
}

/// Represents the broadcast and presence options for a channel.
public struct RealtimeChannelOptions {
  /// Used to track presence payload across clients. Must be unique per client. If `nil`, the server
  /// will generate one.
  var presenceKey: String?
  /// Enables the client to receive their own`broadcast` messages
  var broadcastSelf: Bool
  /// Instructs the server to acknowledge the client's `broadcast` messages
  var broadcastAcknowledge: Bool

  public init(
    presenceKey: String? = nil,
    broadcastSelf: Bool = false,
    broadcastAcknowledge: Bool = false
  ) {
    self.presenceKey = presenceKey
    self.broadcastSelf = broadcastSelf
    self.broadcastAcknowledge = broadcastAcknowledge
  }

  /// Parameters used to configure the channel
  var params: [String: AnyJSON] {
    [
      "config": [
        "presence": [
          "key": .string(presenceKey ?? ""),
        ],
        "broadcast": [
          "ack": .bool(broadcastAcknowledge),
          "self": .bool(broadcastSelf),
        ],
      ],
    ]
  }
}

/// Represents the different status of a push
public enum PushStatus: String {
  case ok
  case error
  case timeout
}

public enum RealtimeSubscribeStates {
  case subscribed
  case timedOut
  case closed
  case channelError
}

///
/// Represents a RealtimeChannel which is bound to a topic
///
/// A RealtimeChannel can bind to multiple events on a given topic and
/// be informed when those events occur within a topic.
///
/// ### Example:
///
///     let channel = socket.channel("room:123", params: ["token": "Room Token"])
///     channel.on("new_msg") { payload in print("Got message", payload") }
///     channel.push("new_msg, payload: ["body": "This is a message"])
///         .receive("ok") { payload in print("Sent message", payload) }
///         .receive("error") { payload in print("Send failed", payload) }
///         .receive("timeout") { payload in print("Networking issue...", payload) }
///
///     channel.join()
///         .receive("ok") { payload in print("RealtimeChannel Joined", payload) }
///         .receive("error") { payload in print("Failed ot join", payload) }
///         .receive("timeout") { payload in print("Networking issue...", payload) }
///

public class RealtimeChannel {
  /// The topic of the RealtimeChannel. e.g. "rooms:friends"
  public let topic: String

  /// The params sent when joining the channel
  public var params: Payload {
    didSet { joinPush.payload = params }
  }

  public private(set) lazy var presence = Presence(channel: self)

  /// The Socket that the channel belongs to
  weak var socket: RealtimeClient?

  var subTopic: String

  /// Current state of the RealtimeChannel
  var state: ChannelState

  /// Collection of event bindings
  let bindings: LockIsolated<[String: [Binding]]>

  /// Timeout when attempting to join a RealtimeChannel
  var timeout: TimeInterval

  /// Set to true once the channel calls .join()
  var joinedOnce: Bool

  /// Push to send when the channel calls .join()
  var joinPush: Push!

  /// Buffer of Pushes that will be sent once the RealtimeChannel's socket connects
  var pushBuffer: [Push]

  /// Timer to attempt to rejoin
  var rejoinTimer: TimeoutTimer

  /// Refs of stateChange hooks
  var stateChangeRefs: [String]

  /// Initialize a RealtimeChannel
  ///
  /// - parameter topic: Topic of the RealtimeChannel
  /// - parameter params: Optional. Parameters to send when joining.
  /// - parameter socket: Socket that the channel is a part of
  init(topic: String, params: [String: AnyJSON] = [:], socket: RealtimeClient) {
    state = ChannelState.closed
    self.topic = topic
    subTopic = topic.replacingOccurrences(of: "realtime:", with: "")
    self.params = params
    self.socket = socket
    bindings = LockIsolated([:])
    timeout = socket.timeout
    joinedOnce = false
    pushBuffer = []
    stateChangeRefs = []
    rejoinTimer = TimeoutTimer()

    // Setup Timer delegation
    rejoinTimer.callback = { [weak self] in
      if self?.socket?.isConnected == true {
        self?.rejoin()
      }
    }

    rejoinTimer.timerCalculation = { [weak self] tries in
      self?.socket?.rejoinAfter(tries) ?? 5.0
    }

    // Respond to socket events
    let onErrorRef = self.socket?.onError { [weak self] _, _ in
      self?.rejoinTimer.reset()
    }

    if let ref = onErrorRef {
      stateChangeRefs.append(ref)
    }

    let onOpenRef = self.socket?.onOpen { [weak self] in
      self?.rejoinTimer.reset()
      if self?.isErrored == true {
        self?.rejoin()
      }
    }

    if let ref = onOpenRef { stateChangeRefs.append(ref) }

    // Setup Push Event to be sent when joining
    joinPush = Push(
      channel: self,
      event: ChannelEvent.join,
      payload: self.params,
      timeout: timeout
    )

    /// Handle when a response is received after join()
    joinPush.receive(.ok) { [weak self] _ in
      // Mark the RealtimeChannel as joined
      self?.state = ChannelState.joined

      // Reset the timer, preventing it from attempting to join again
      self?.rejoinTimer.reset()

      // Send and buffered messages and clear the buffer
      self?.pushBuffer.forEach { $0.send() }
      self?.pushBuffer = []
    }

    // Perform if RealtimeChannel errors while attempting to joi
    joinPush.receive(.error) { [weak self] _ in
      self?.state = .errored
      if self?.socket?.isConnected == true {
        self?.rejoinTimer.scheduleTimeout()
      }
    }

    // Handle when the join push times out when sending after join()
    joinPush.receive(.timeout) { [weak self] _ in
      guard let self else { return }

      // log that the channel timed out
      self.socket?.logItems(
        "channel", "timeout \(self.topic) \(self.joinRef ?? "") after \(self.timeout)s"
      )

      // Send a Push to the server to leave the channel
      let leavePush = Push(
        channel: self,
        event: ChannelEvent.leave,
        timeout: self.timeout
      )
      leavePush.send()

      // Mark the RealtimeChannel as in an error and attempt to rejoin if socket is connected
      self.state = ChannelState.errored
      self.joinPush.reset()

      if self.socket?.isConnected == true { self.rejoinTimer.scheduleTimeout() }
    }

    /// Perform when the RealtimeChannel has been closed
    onClose { [weak self] _ in
      guard let self else { return }

      // Reset any timer that may be on-going
      self.rejoinTimer.reset()

      // Log that the channel was left
      self.socket?.logItems(
        "channel", "close topic: \(self.topic) joinRef: \(self.joinRef ?? "nil")"
      )

      // Mark the channel as closed and remove it from the socket
      self.state = ChannelState.closed
      self.socket?.remove(self)
    }

    /// Perform when the RealtimeChannel errors
    onError { [weak self] message in
      guard let self else { return }

      // Log that the channel received an error
      self.socket?.logItems(
        "channel", "error topic: \(self.topic) joinRef: \(self.joinRef ?? "nil") mesage: \(message)"
      )

      // If error was received while joining, then reset the Push
      if self.isJoining {
        // Make sure that the "phx_join" isn't buffered to send once the socket
        // reconnects. The channel will send a new join event when the socket connects.
        if let safeJoinRef = self.joinRef {
          self.socket?.removeFromSendBuffer(ref: safeJoinRef)
        }

        // Reset the push to be used again later
        self.joinPush.reset()
      }

      // Mark the channel as errored and attempt to rejoin if socket is currently connected
      self.state = ChannelState.errored
      if self.socket?.isConnected == true { self.rejoinTimer.scheduleTimeout() }
    }

    // Perform when the join reply is received
    on(ChannelEvent.reply, filter: ChannelFilter()) { [weak self] message in
      guard let self else { return }

      // Trigger bindings
      self.trigger(
        event: self.replyEventName(message.ref),
        payload: message.rawPayload,
        ref: message.ref,
        joinRef: message.joinRef
      )
    }
  }

  deinit {
    rejoinTimer.reset()
  }

  /// Overridable message hook. Receives all events for specialized message
  /// handling before dispatching to the channel callbacks.
  ///
  /// - parameter msg: The Message received by the client from the server
  /// - return: Must return the message, modified or unmodified
  public var onMessage: (_ message: Message) -> Message = { message in
    message
  }

  /// Joins the channel
  ///
  /// - parameter timeout: Optional. Defaults to RealtimeChannel's timeout
  /// - return: Push event
  @discardableResult
  public func subscribe(
    timeout: TimeInterval? = nil,
    callback: ((RealtimeSubscribeStates, Error?) -> Void)? = nil
  ) -> RealtimeChannel {
    guard !joinedOnce else {
      fatalError(
        "tried to join multiple times. 'join' "
          + "can only be called a single time per channel instance"
      )
    }

    onError { message in
      let values = message.payload.values.map { "\($0) " }
      let error = RealtimeError(values.isEmpty ? "error" : values.joined(separator: ", "))
      callback?(.channelError, error)
    }

    onClose { _ in
      callback?(.closed, nil)
    }

    // Join the RealtimeChannel
    if let safeTimeout = timeout {
      self.timeout = safeTimeout
    }

    let broadcast = params["config"]?.objectValue?["broadcast"]
    let presence = params["config"]?.objectValue?["presence"]

    var accessTokenPayload: Payload = [:]

    var config: Payload = [
      "postgres_changes": .array(
        (bindings["postgres_changes"]?.map(\.filter) ?? []).map { filter in
          AnyJSON.object(filter.mapValues(AnyJSON.string))
        }
      ),
    ]

    config["broadcast"] = broadcast
    config["presence"] = presence

    if let accessToken = socket?.accessToken {
      accessTokenPayload["access_token"] = .string(accessToken)
    }

    params["config"] = .object(config)

    joinedOnce = true
    rejoin()

    joinPush
      .receive(.ok) { [weak self] message in
        guard let self else {
          return
        }

        if self.socket?.accessToken != nil {
          self.socket?.setAuth(self.socket?.accessToken)
        }

        guard let serverPostgresFilters = message.payload["postgres_changes"]?.arrayValue?
          .compactMap(\.objectValue)
        else {
          callback?(.subscribed, nil)
          return
        }

        let clientPostgresBindings = self.bindings.value["postgres_changes"] ?? []
        let bindingsCount = clientPostgresBindings.count
        var newPostgresBindings: [Binding] = []

        for i in 0 ..< bindingsCount {
          let clientPostgresBinding = clientPostgresBindings[i]

          let event = clientPostgresBinding.filter["event"]
          let schema = clientPostgresBinding.filter["schema"]
          let table = clientPostgresBinding.filter["table"]
          let filter = clientPostgresBinding.filter["filter"]

          let serverPostgresFilter = serverPostgresFilters[i]

          if serverPostgresFilter["event"]?.stringValue == event,
             serverPostgresFilter["schema"]?.stringValue == schema,
             serverPostgresFilter["table"]?.stringValue == table,
             serverPostgresFilter["filter"]?.stringValue == filter
          {
            newPostgresBindings.append(
              Binding(
                type: clientPostgresBinding.type,
                filter: clientPostgresBinding.filter,
                callback: clientPostgresBinding.callback,
                id: serverPostgresFilter["id"]?.numberValue.map { Int($0) }.flatMap(String.init)
              )
            )
          } else {
            self.unsubscribe()
            callback?(
              .channelError,
              RealtimeError("Mismatch between client and server bindings for postgres changes.")
            )
            return
          }
        }

        self.bindings.withValue { [newPostgresBindings] in
          $0["postgres_changes"] = newPostgresBindings
        }
        callback?(.subscribed, nil)
      }
      .receive(.error) { message in
        let values = message.payload.values.map { "\($0) " }
        let error = RealtimeError(values.isEmpty ? "error" : values.joined(separator: ", "))
        callback?(.channelError, error)
      }
      .receive(.timeout) { _ in
        callback?(.timedOut, nil)
      }

    return self
  }

  public func presenceState() -> Presence.State {
    presence.state
  }

  public func track(_ payload: Payload, opts: Payload = [:]) async -> ChannelResponse {
    await send(
      type: .presence,
      payload: [
        "event": "track",
        "payload": .object(payload),
      ],
      opts: opts
    )
  }

  public func untrack(opts: Payload = [:]) async -> ChannelResponse {
    await send(
      type: .presence,
      payload: ["event": "untrack"],
      opts: opts
    )
  }

  /// Hook into when the RealtimeChannel is closed. Does not handle retain cycles.
  /// Use `delegateOnClose(to:)` for automatic handling of retain cycles.
  ///
  /// Example:
  ///
  ///     let channel = socket.channel("topic")
  ///     channel.onClose() { [weak self] message in
  ///         self?.print("RealtimeChannel \(message.topic) has closed"
  ///     }
  ///
  /// - parameter handler: Called when the RealtimeChannel closes
  /// - return: Ref counter of the subscription. See `func off()`
  @discardableResult
  public func onClose(_ handler: @escaping @Sendable (Message) -> Void) -> RealtimeChannel {
    on(ChannelEvent.close, filter: ChannelFilter(), handler: handler)
  }

  /// Hook into when the RealtimeChannel receives an Error. Does not handle retain
  /// cycles. Use `delegateOnError(to:)` for automatic handling of retain
  /// cycles.
  ///
  /// Example:
  ///
  ///     let channel = socket.channel("topic")
  ///     channel.onError() { [weak self] (message) in
  ///         self?.print("RealtimeChannel \(message.topic) has errored"
  ///     }
  ///
  /// - parameter handler: Called when the RealtimeChannel closes
  /// - return: Ref counter of the subscription. See `func off()`
  @discardableResult
  public func onError(_ handler: @escaping @Sendable (_ message: Message) -> Void)
    -> RealtimeChannel
  {
    on(ChannelEvent.error, filter: ChannelFilter(), handler: handler)
  }

  /// Subscribes on channel events. Does not handle retain cycles. Use
  /// `delegateOn(_:, to:)` for automatic handling of retain cycles.
  ///
  /// Subscription returns a ref counter, which can be used later to
  /// unsubscribe the exact event listener
  ///
  /// Example:
  ///
  ///     let channel = socket.channel("topic")
  ///     let ref1 = channel.on("event") { [weak self] (message) in
  ///         self?.print("do stuff")
  ///     }
  ///     let ref2 = channel.on("event") { [weak self] (message) in
  ///         self?.print("do other stuff")
  ///     }
  ///     channel.off("event", ref1)
  ///
  /// Since unsubscription of ref1, "do stuff" won't print, but "do other
  /// stuff" will keep on printing on the "event"
  ///
  /// - parameter event: Event to receive
  /// - parameter handler: Called with the event's message
  /// - return: Ref counter of the subscription. See `func off()`
  @discardableResult
  public func on(
    _ event: String,
    filter: ChannelFilter,
    handler: @escaping @Sendable (Message) -> Void
  ) -> RealtimeChannel {
    bindings.withValue {
      $0[event.lowercased(), default: []].append(
        Binding(type: event.lowercased(), filter: filter.asDictionary, callback: handler, id: nil)
      )
    }

    return self
  }

  /// Unsubscribes from a channel event. If a `ref` is given, only the exact
  /// listener will be removed. Else all listeners for the `event` will be
  /// removed.
  ///
  /// Example:
  ///
  ///     let channel = socket.channel("topic")
  ///     let ref1 = channel.on("event") { _ in print("ref1 event" }
  ///     let ref2 = channel.on("event") { _ in print("ref2 event" }
  ///     let ref3 = channel.on("other_event") { _ in print("ref3 other" }
  ///     let ref4 = channel.on("other_event") { _ in print("ref4 other" }
  ///     channel.off("event", ref1)
  ///     channel.off("other_event")
  ///
  /// After this, only "ref2 event" will be printed if the channel receives
  /// "event" and nothing is printed if the channel receives "other_event".
  ///
  /// - parameter event: Event to unsubscribe from
  /// - parameter ref: Ref counter returned when subscribing. Can be omitted
  public func off(_ type: String, filter: [String: String] = [:]) {
    bindings.withValue {
      $0[type.lowercased()] = $0[type.lowercased(), default: []].filter { bind in
        !(bind.type.lowercased() == type.lowercased() && bind.filter == filter)
      }
    }
  }

  /// Push a payload to the RealtimeChannel
  ///
  /// Example:
  ///
  ///     channel
  ///         .push("event", payload: ["message": "hello")
  ///         .receive("ok") { _ in { print("message sent") }
  ///
  /// - parameter event: Event to push
  /// - parameter payload: Payload to push
  /// - parameter timeout: Optional timeout
  @discardableResult
  public func push(
    _ event: String,
    payload: Payload,
    timeout: TimeInterval = Defaults.timeoutInterval
  ) -> Push {
    guard joinedOnce else {
      fatalError(
        "Tried to push \(event) to \(topic) before joining. Use channel.join() before pushing events"
      )
    }

    let pushEvent = Push(
      channel: self,
      event: event,
      payload: payload,
      timeout: timeout
    )
    if canPush {
      pushEvent.send()
    } else {
      pushEvent.startTimeout()
      pushBuffer.append(pushEvent)
    }

    return pushEvent
  }

  public func send(
    type: RealtimeListenTypes,
    event: String? = nil,
    payload: Payload,
    opts: Payload = [:]
  ) async -> ChannelResponse {
    var payload = payload
    payload["type"] = .string(type.rawValue)
    if let event {
      payload["event"] = .string(event)
    }

    if !canPush, type == .broadcast {
      var headers = socket?.headers ?? [:]
      headers["Content-Type"] = "application/json"
      headers["apikey"] = socket?.accessToken

      let body = [
        "messages": [
          "topic": subTopic,
          "payload": payload,
          "event": event as Any,
        ],
      ]

      do {
        let request = try Request(
          path: "",
          method: .post,
          headers: headers.mapValues { "\($0)" },
          body: JSONSerialization.data(withJSONObject: body)
        )

        let response = try await socket?.http.fetch(request, baseURL: broadcastEndpointURL)
        guard let response, 200 ..< 300 ~= response.statusCode else {
          return .error
        }
        return .ok
      } catch {
        return .error
      }
    } else {
      return await withCheckedContinuation { continuation in
        let push = self.push(
          type.rawValue, payload: payload,
          timeout: opts["timeout"]?.numberValue ?? self.timeout
        )

        if let type = payload["type"]?.stringValue, type == "broadcast",
           let config = self.params["config"]?.objectValue,
           let broadcast = config["broadcast"]?.objectValue
        {
          let ack = broadcast["ack"]?.boolValue
          if ack == nil || ack == false {
            continuation.resume(returning: .ok)
            return
          }
        }

        push
          .receive(.ok) { _ in
            continuation.resume(returning: .ok)
          }
          .receive(.timeout) { _ in
            continuation.resume(returning: .timedOut)
          }
      }
    }
  }

  /// Leaves the channel
  ///
  /// Unsubscribes from server events, and instructs channel to terminate on
  /// server
  ///
  /// Triggers onClose() hooks
  ///
  /// To receive leave acknowledgements, use the a `receive`
  /// hook to bind to the server ack, ie:
  ///
  /// Example:
  ////
  ///     channel.leave().receive("ok") { _ in { print("left") }
  ///
  /// - parameter timeout: Optional timeout
  /// - return: Push that can add receive hooks
  @discardableResult
  public func unsubscribe(timeout: TimeInterval = Defaults.timeoutInterval) -> Push {
    // If attempting a rejoin during a leave, then reset, cancelling the rejoin
    rejoinTimer.reset()

    // Now set the state to leaving
    state = .leaving

    /// onClose callback for a successful or a failed channel leave
    let onCloseCallback: @Sendable (Message) -> Void = { [weak self] _ in
      guard let self else { return }

      self.socket?.logItems("channel", "leave \(self.topic)")

      // Triggers onClose() hooks
      self.trigger(event: ChannelEvent.close, payload: ["reason": "leave"])
    }

    // Push event to send to the server
    let leavePush = Push(
      channel: self,
      event: ChannelEvent.leave,
      timeout: timeout
    )

    // Perform the same behavior if successfully left the channel
    // or if sending the event timed out
    leavePush
      .receive(.ok, callback: onCloseCallback)
      .receive(.timeout, callback: onCloseCallback)
    leavePush.send()

    // If the RealtimeChannel cannot send push events, trigger a success locally
    if !canPush {
      leavePush.trigger(.ok, payload: [:])
    }

    // Return the push so it can be bound to
    return leavePush
  }

  /// Overridable message hook. Receives all events for specialized message
  /// handling before dispatching to the channel callbacks.
  ///
  /// - parameter event: The event the message was for
  /// - parameter payload: The payload for the message
  /// - parameter ref: The reference of the message
  /// - return: Must return the payload, modified or unmodified
  public func onMessage(callback: @escaping (Message) -> Message) {
    onMessage = callback
  }

  // ----------------------------------------------------------------------

  // MARK: - Internal

  // ----------------------------------------------------------------------
  /// Checks if an event received by the Socket belongs to this RealtimeChannel
  func isMember(_ message: Message) -> Bool {
    // Return false if the message's topic does not match the RealtimeChannel's topic
    guard message.topic == topic else { return false }

    guard
      let safeJoinRef = message.joinRef,
      safeJoinRef != joinRef,
      ChannelEvent.isLifecyleEvent(message.event)
    else { return true }

    socket?.logItems(
      "channel", "dropping outdated message", message.topic, message.event, message.rawPayload,
      safeJoinRef
    )
    return false
  }

  /// Sends the payload to join the RealtimeChannel
  func sendJoin(_ timeout: TimeInterval) {
    state = ChannelState.joining
    joinPush.resend(timeout)
  }

  /// Rejoins the channel
  func rejoin(_ timeout: TimeInterval? = nil) {
    // Do not attempt to rejoin if the channel is in the process of leaving
    guard !isLeaving else { return }

    // Leave potentially duplicate channels
    socket?.leaveOpenTopic(topic: topic)

    // Send the joinPush
    sendJoin(timeout ?? self.timeout)
  }

  /// Triggers an event to the correct event bindings created by
  /// `channel.on("event")`.
  ///
  /// - parameter message: Message to pass to the event bindings
  func trigger(_ message: Message) {
    let typeLower = message.event.lowercased()

    let events = Set([
      ChannelEvent.close,
      ChannelEvent.error,
      ChannelEvent.leave,
      ChannelEvent.join,
    ])

    if message.ref != message.joinRef, events.contains(typeLower) {
      return
    }

    let handledMessage = onMessage(message)

    if ["insert", "update", "delete"].contains(typeLower) {
      let bindings = (bindings["postgres_changes"] ?? []).filter { bind in
        bind.filter["event"] == "*" || bind.filter["event"] == typeLower
      }
      bindings.forEach { $0.callback(handledMessage) }
    } else {
      let b = bindings[typeLower] ?? []

      let bindings = b.filter { bind -> Bool in
        if ["broadcast", "presence", "postgres_changes"].contains(typeLower) {
          let bindEvent = bind.filter["event"]?.lowercased()

          if let bindId = bind.id.flatMap(Int.init) {
            let ids = (message.payload["ids"]?.arrayValue ?? []).compactMap(\.numberValue)
              .map(Int.init)
            let data = message.payload["data"]?.objectValue ?? [:]
            let type = data["type"]?.stringValue
            return ids.contains(bindId) && (bindEvent == "*" || bindEvent == type?.lowercased())
          }

          let messageEvent = message.payload["event"]?.stringValue
          return bindEvent == "*" || bindEvent == messageEvent?.lowercased()
        }

        return bind.type.lowercased() == typeLower
      }

      bindings.forEach { $0.callback(handledMessage) }
    }
  }

  /// Triggers an event to the correct event bindings created by
  //// `channel.on("event")`.
  ///
  /// - parameter event: Event to trigger
  /// - parameter payload: Payload of the event
  /// - parameter ref: Ref of the event. Defaults to empty
  /// - parameter joinRef: Ref of the join event. Defaults to nil
  func trigger(
    event: String,
    payload: Payload = [:],
    ref: String = "",
    joinRef: String? = nil
  ) {
    let message = Message(
      ref: ref,
      topic: topic,
      event: event,
      payload: payload,
      joinRef: joinRef ?? self.joinRef
    )
    trigger(message)
  }

  /// - parameter ref: The ref of the event push
  /// - return: The event name of the reply
  func replyEventName(_ ref: String) -> String {
    "chan_reply_\(ref)"
  }

  /// The Ref send during the join message.
  var joinRef: String? {
    joinPush.ref
  }

  /// - return: True if the RealtimeChannel can push messages, meaning the socket
  ///           is connected and the channel is joined
  var canPush: Bool {
    socket?.isConnected == true && isJoined
  }

  var broadcastEndpointURL: URL {
    var url = socket?.url.absoluteString ?? ""

    url = url.replacingOccurrences(of: "^ws", with: "http", options: .regularExpression, range: nil)
    url = url.replacingOccurrences(
      of: "(/socket/websocket|/socket|/websocket)/?$", with: "", options: .regularExpression,
      range: nil
    )
    url =
      "\(url.replacingOccurrences(of: "/+$", with: "", options: .regularExpression, range: nil))/api/broadcast"
    return URL(string: url)!
  }
}

// ----------------------------------------------------------------------

// MARK: - Public API

// ----------------------------------------------------------------------
extension RealtimeChannel {
  /// - return: True if the RealtimeChannel has been closed
  public var isClosed: Bool {
    state == .closed
  }

  /// - return: True if the RealtimeChannel experienced an error
  public var isErrored: Bool {
    state == .errored
  }

  /// - return: True if the channel has joined
  public var isJoined: Bool {
    state == .joined
  }

  /// - return: True if the channel has requested to join
  public var isJoining: Bool {
    state == .joining
  }

  /// - return: True if the channel has requested to leave
  public var isLeaving: Bool {
    state == .leaving
  }
}
