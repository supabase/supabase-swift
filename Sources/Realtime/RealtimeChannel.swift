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

import ConcurrencyExtras
import Foundation
import Helpers
import Swift

/// Container class of bindings to the channel
struct Binding {
  let type: String
  let filter: [String: String]

  // The callback to be triggered
  let callback: Delegated<RealtimeMessage, Void>

  let id: String?
}

public struct ChannelFilter {
  public var event: String?
  public var schema: String?
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
  var params: [String: [String: Any]] {
    [
      "config": [
        "presence": [
          "key": presenceKey ?? "",
        ],
        "broadcast": [
          "ack": broadcastAcknowledge,
          "self": broadcastSelf,
        ],
      ],
    ]
  }
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
@available(
  *,
  deprecated,
  message: "Use new RealtimeChannelV2 class instead. See migration guide: https://github.com/supabase-community/supabase-swift/blob/main/docs/migrations/RealtimeV2%20Migration%20Guide.md"
)
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
  init(topic: String, params: [String: Any] = [:], socket: RealtimeClient) {
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

    // Setup Timer delgation
    rejoinTimer.callback
      .delegate(to: self) { (self) in
        if self.socket?.isConnected == true { self.rejoin() }
      }

    rejoinTimer.timerCalculation
      .delegate(to: self) { (self, tries) -> TimeInterval in
        self.socket?.rejoinAfter(tries) ?? 5.0
      }

    // Respond to socket events
    let onErrorRef = self.socket?.delegateOnError(
      to: self,
      callback: { (self, _) in
        self.rejoinTimer.reset()
      }
    )
    if let ref = onErrorRef { stateChangeRefs.append(ref) }

    let onOpenRef = self.socket?.delegateOnOpen(
      to: self,
      callback: { (self) in
        self.rejoinTimer.reset()
        if self.isErrored { self.rejoin() }
      }
    )
    if let ref = onOpenRef { stateChangeRefs.append(ref) }

    // Setup Push Event to be sent when joining
    joinPush = Push(
      channel: self,
      event: ChannelEvent.join,
      payload: self.params,
      timeout: timeout
    )

    /// Handle when a response is received after join()
    joinPush.delegateReceive(.ok, to: self) { (self, _) in
      // Mark the RealtimeChannel as joined
      self.state = ChannelState.joined

      // Reset the timer, preventing it from attempting to join again
      self.rejoinTimer.reset()

      // Send and buffered messages and clear the buffer
      self.pushBuffer.forEach { $0.send() }
      self.pushBuffer = []
    }

    // Perform if RealtimeChannel errors while attempting to joi
    joinPush.delegateReceive(.error, to: self) { (self, _) in
      self.state = .errored
      if self.socket?.isConnected == true { self.rejoinTimer.scheduleTimeout() }
    }

    // Handle when the join push times out when sending after join()
    joinPush.delegateReceive(.timeout, to: self) { (self, _) in
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

    /// Perfom when the RealtimeChannel has been closed
    delegateOnClose(to: self) { (self, _) in
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

    /// Perfom when the RealtimeChannel errors
    delegateOnError(to: self) { (self, message) in
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
    delegateOn(ChannelEvent.reply, filter: ChannelFilter(), to: self) { (self, message) in
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
  public var onMessage: (_ message: RealtimeMessage) -> RealtimeMessage = { message in
    message
  }

  /// Joins the channel
  ///
  /// - parameter timeout: Optional. Defaults to RealtimeChannel's timeout
  /// - return: Push event
  @discardableResult
  public func subscribe(
    timeout: TimeInterval? = nil,
    callback: ((RealtimeSubscribeStates, (any Error)?) -> Void)? = nil
  ) -> RealtimeChannel {
    if socket?.isConnected == false {
      socket?.connect()
    }

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

    let broadcast = params["config", as: [String: Any].self]?["broadcast"]
    let presence = params["config", as: [String: Any].self]?["presence"]

    var accessTokenPayload: Payload = [:]
    var config: Payload = [
      "postgres_changes": bindings.value["postgres_changes"]?.map(\.filter) ?? [],
    ]

    config["broadcast"] = broadcast
    config["presence"] = presence

    if let accessToken = socket?.accessToken {
      accessTokenPayload["access_token"] = accessToken
    }

    params["config"] = config

    joinedOnce = true
    rejoin()

    joinPush
      .delegateReceive(.ok, to: self) { (self, message) in
        if self.socket?.accessToken != nil {
          self.socket?.setAuth(self.socket?.accessToken)
        }

        guard let serverPostgresFilters = message.payload["postgres_changes"] as? [[String: Any]]
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

          if serverPostgresFilter["event", as: String.self] == event,
             serverPostgresFilter["schema", as: String.self] == schema,
             serverPostgresFilter["table", as: String.self] == table,
             serverPostgresFilter["filter", as: String.self] == filter
          {
            newPostgresBindings.append(
              Binding(
                type: clientPostgresBinding.type,
                filter: clientPostgresBinding.filter,
                callback: clientPostgresBinding.callback,
                id: serverPostgresFilter["id", as: Int.self].flatMap(String.init)
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
      .delegateReceive(.error, to: self) { _, message in
        let values = message.payload.values.map { "\($0) " }
        let error = RealtimeError(values.isEmpty ? "error" : values.joined(separator: ", "))
        callback?(.channelError, error)
      }
      .delegateReceive(.timeout, to: self) { _, _ in
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
        "payload": payload,
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
  public func onClose(_ handler: @escaping ((RealtimeMessage) -> Void)) -> RealtimeChannel {
    on(ChannelEvent.close, filter: ChannelFilter(), handler: handler)
  }

  /// Hook into when the RealtimeChannel is closed. Automatically handles retain
  /// cycles. Use `onClose()` to handle yourself.
  ///
  /// Example:
  ///
  ///     let channel = socket.channel("topic")
  ///     channel.delegateOnClose(to: self) { (self, message) in
  ///         self.print("RealtimeChannel \(message.topic) has closed"
  ///     }
  ///
  /// - parameter owner: Class registering the callback. Usually `self`
  /// - parameter callback: Called when the RealtimeChannel closes
  /// - return: Ref counter of the subscription. See `func off()`
  @discardableResult
  public func delegateOnClose<Target: AnyObject>(
    to owner: Target,
    callback: @escaping ((Target, RealtimeMessage) -> Void)
  ) -> RealtimeChannel {
    delegateOn(
      ChannelEvent.close, filter: ChannelFilter(), to: owner, callback: callback
    )
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
  public func onError(_ handler: @escaping ((_ message: RealtimeMessage) -> Void))
    -> RealtimeChannel
  {
    on(ChannelEvent.error, filter: ChannelFilter(), handler: handler)
  }

  /// Hook into when the RealtimeChannel receives an Error. Automatically handles
  /// retain cycles. Use `onError()` to handle yourself.
  ///
  /// Example:
  ///
  ///     let channel = socket.channel("topic")
  ///     channel.delegateOnError(to: self) { (self, message) in
  ///         self.print("RealtimeChannel \(message.topic) has closed"
  ///     }
  ///
  /// - parameter owner: Class registering the callback. Usually `self`
  /// - parameter callback: Called when the RealtimeChannel closes
  /// - return: Ref counter of the subscription. See `func off()`
  @discardableResult
  public func delegateOnError<Target: AnyObject>(
    to owner: Target,
    callback: @escaping ((Target, RealtimeMessage) -> Void)
  ) -> RealtimeChannel {
    delegateOn(
      ChannelEvent.error, filter: ChannelFilter(), to: owner, callback: callback
    )
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
    handler: @escaping ((RealtimeMessage) -> Void)
  ) -> RealtimeChannel {
    var delegated = Delegated<RealtimeMessage, Void>()
    delegated.manuallyDelegate(with: handler)

    return on(event, filter: filter, delegated: delegated)
  }

  /// Subscribes on channel events. Automatically handles retain cycles. Use
  /// `on()` to handle yourself.
  ///
  /// Subscription returns a ref counter, which can be used later to
  /// unsubscribe the exact event listener
  ///
  /// Example:
  ///
  ///     let channel = socket.channel("topic")
  ///     let ref1 = channel.delegateOn("event", to: self) { (self, message) in
  ///         self?.print("do stuff")
  ///     }
  ///     let ref2 = channel.delegateOn("event", to: self) { (self, message) in
  ///         self?.print("do other stuff")
  ///     }
  ///     channel.off("event", ref1)
  ///
  /// Since unsubscription of ref1, "do stuff" won't print, but "do other
  /// stuff" will keep on printing on the "event"
  ///
  /// - parameter event: Event to receive
  /// - parameter owner: Class registering the callback. Usually `self`
  /// - parameter callback: Called with the event's message
  /// - return: Ref counter of the subscription. See `func off()`
  @discardableResult
  public func delegateOn<Target: AnyObject>(
    _ event: String,
    filter: ChannelFilter,
    to owner: Target,
    callback: @escaping ((Target, RealtimeMessage) -> Void)
  ) -> RealtimeChannel {
    var delegated = Delegated<RealtimeMessage, Void>()
    delegated.delegate(to: owner, with: callback)

    return on(event, filter: filter, delegated: delegated)
  }

  /// Shared method between `on` and `manualOn`
  @discardableResult
  private func on(
    _ type: String, filter: ChannelFilter, delegated: Delegated<RealtimeMessage, Void>
  ) -> RealtimeChannel {
    bindings.withValue {
      $0[type.lowercased(), default: []].append(
        Binding(type: type.lowercased(), filter: filter.asDictionary, callback: delegated, id: nil)
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
    payload["type"] = type.rawValue
    if let event {
      payload["event"] = event
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
        let request = try HTTPRequest(
          url: broadcastEndpointURL,
          method: .post,
          headers: HTTPHeaders(headers.mapValues { "\($0)" }),
          body: JSONSerialization.data(withJSONObject: body)
        )

        let response = try await socket?.http.send(request)
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
          timeout: (opts["timeout"] as? TimeInterval) ?? self.timeout
        )

        if let type = payload["type"] as? String, type == "broadcast",
           let config = self.params["config"] as? [String: Any],
           let broadcast = config["broadcast"] as? [String: Any]
        {
          let ack = broadcast["ack"] as? Bool
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

    /// Delegated callback for a successful or a failed channel leave
    var onCloseDelegate = Delegated<RealtimeMessage, Void>()
    onCloseDelegate.delegate(to: self) { (self, _) in
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
      .receive(.ok, delegated: onCloseDelegate)
      .receive(.timeout, delegated: onCloseDelegate)
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
  public func onMessage(callback: @escaping (RealtimeMessage) -> RealtimeMessage) {
    onMessage = callback
  }

  // ----------------------------------------------------------------------

  // MARK: - Internal

  // ----------------------------------------------------------------------
  /// Checks if an event received by the Socket belongs to this RealtimeChannel
  func isMember(_ message: RealtimeMessage) -> Bool {
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
  func trigger(_ message: RealtimeMessage) {
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

    let handledMessage = message

    let bindings: [Binding] = if ["insert", "update", "delete"].contains(typeLower) {
      self.bindings.value["postgres_changes", default: []].filter { bind in
        bind.filter["event"] == "*" || bind.filter["event"] == typeLower
      }
    } else {
      self.bindings.value[typeLower, default: []].filter { bind in
        if ["broadcast", "presence", "postgres_changes"].contains(typeLower) {
          let bindEvent = bind.filter["event"]?.lowercased()

          if let bindId = bind.id.flatMap(Int.init) {
            let ids = message.payload["ids", as: [Int].self] ?? []
            return ids.contains(bindId)
              && (
                bindEvent == "*"
                  || bindEvent
                  == message.payload["data", as: [String: Any].self]?["type", as: String.self]?
                  .lowercased()
              )
          }

          return bindEvent == "*"
            || bindEvent == message.payload["event", as: String.self]?.lowercased()
        }

        return bind.type.lowercased() == typeLower
      }
    }

    bindings.forEach { $0.callback.call(handledMessage) }
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
    let message = RealtimeMessage(
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
    var url = socket?.endPoint ?? ""
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

extension [String: Any] {
  subscript<T>(_ key: Key, as _: T.Type) -> T? {
    self[key] as? T
  }
}
