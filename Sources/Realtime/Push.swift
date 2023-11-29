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

/// Represents pushing data to a `Channel` through the `Socket`
public final class Push: @unchecked Sendable {
  struct MutableState {
    var channel: RealtimeChannel?
    var payload: Payload = [:]
    var timeout: TimeInterval = Defaults.timeoutInterval

    /// The server's response to the Push
    var receivedMessage: Message?

    /// Timer which triggers a timeout event
    var timeoutTask: Task<Void, Never>?

    /// Hooks into a Push. Where .receive("ok", callback(Payload)) are stored
    var receiveHooks: [PushStatus: [@MainActor @Sendable (Message) -> Void]] = [:]

    /// True if the Push has been sent
    var sent: Bool = false

    /// The reference ID of the Push
    var ref: String?

    /// The event that is associated with the reference ID of the Push
    var refEvent: String?

    /// Reverses the result on channel.on(ChannelEvent, callback) that spawned the Push
    mutating func cancelRefEvent() {
      guard let refEvent else { return }
      channel?.off(refEvent)
    }
  }

  private let mutableState = LockIsolated(MutableState())

  /// The event, for example `phx_join`
  public let event: String

  /// The payload, for example ["user_id": "abc123"]
  public var payload: Payload {
    get { mutableState.payload }
    set { mutableState.withValue { $0.payload = newValue } }
  }

  /// The reference ID of the Push
  var ref: String? {
    mutableState.ref
  }

  /// Initializes a Push
  ///
  /// - parameter channel: The Channel
  /// - parameter event: The event, for example ChannelEvent.join
  /// - parameter payload: Optional. The Payload to send, e.g. ["user_id": "abc123"]
  /// - parameter timeout: Optional. The push timeout. Default is 10.0s
  init(
    channel: RealtimeChannel,
    event: String,
    payload: Payload = [:],
    timeout: TimeInterval = Defaults.timeoutInterval
  ) {
    mutableState.withValue {
      $0.channel = channel
      $0.payload = payload
      $0.timeout = timeout
    }
    self.event = event
  }

  /// Resets and sends the Push
  /// - parameter timeout: Optional. The push timeout. Default is 10.0s
  public func resend(_ timeout: TimeInterval = Defaults.timeoutInterval) {
    mutableState.withValue {
      $0.timeout = timeout
    }
    reset()
    send()
  }

  /// Sends the Push. If it has already timed out, then the call will
  /// be ignored and return early. Use `resend` in this case.
  public func send() {
    guard !hasReceived(status: .timeout) else { return }

    startTimeout()
    mutableState.withValue {
      $0.sent = true
    }

    let channel = mutableState.channel

    channel?.socket?.push(
      message: Message(
        ref: mutableState.ref ?? "",
        topic: channel?.topic ?? "",
        event: event,
        payload: payload,
        joinRef: channel?.joinRef
      )
    )
  }

  /// Receive a specific event when sending an Outbound message. Subscribing
  /// to status events with this method does not guarantees no retain cycles.
  /// You should pass `weak self` in the capture list of the callback. You
  /// can call `.delegateReceive(status:, to:, callback:) and the library will
  /// handle it for you.
  ///
  /// Example:
  ///
  ///     channel
  ///         .send(event:"custom", payload: ["body": "example"])
  ///         .receive("error") { [weak self] payload in
  ///             print("Error: ", payload)
  ///         }
  ///
  /// - parameter status: Status to receive
  /// - parameter callback: Callback to fire when the status is recevied
  @discardableResult
  public func receive(
    _ status: PushStatus,
    callback: @MainActor @escaping @Sendable (Message) -> Void
  ) -> Push {
    // If the message has already been received, pass it to the callback immediately
    if hasReceived(status: status), let receivedMessage = mutableState.receivedMessage {
      Task {
        await callback(receivedMessage)
      }
    }

    mutableState.withValue {
      if $0.receiveHooks[status] == nil {
        /// Create a new array of hooks if no previous hook is associated with status
        $0.receiveHooks[status] = [callback]
      } else {
        /// A previous hook for this status already exists. Just append the new hook
        $0.receiveHooks[status]?.append(callback)
      }
    }

    return self
  }

  /// Resets the Push as it was after it was first initialized.
  func reset() {
    mutableState.withValue {
      $0.cancelRefEvent()
      $0.refEvent = nil
      $0.ref = nil
      $0.receivedMessage = nil
      $0.sent = false
    }
  }

  /// Finds the receiveHook which needs to be informed of a status response
  ///
  /// - parameter status: Status which was received, e.g. "ok", "error", "timeout"
  /// - parameter response: Response that was received
  private func matchReceive(_ status: PushStatus, message: Message) {
    Task {
      for hook in mutableState.receiveHooks[status, default: []] {
        await hook(message)
      }
    }
  }

  /// Cancel any ongoing Timeout Timer
  func cancelTimeout() {
    mutableState.withValue {
      $0.timeoutTask?.cancel()
      $0.timeoutTask = nil
    }
  }

  /// Starts the Timer which will trigger a timeout after a specific _timeout_
  /// time, in milliseconds, is reached.
  func startTimeout() {
    // Cancel any existing timeout before starting a new one
    mutableState.timeoutTask?.cancel()

    guard
      let channel = mutableState.channel,
      let socket = channel.socket
    else { return }

    let ref = socket.makeRef()
    let refEvent = channel.replyEventName(ref)

    mutableState.withValue {
      $0.ref = ref
      $0.refEvent = refEvent
    }

    /// If a response is received  before the Timer triggers, cancel timer
    /// and match the received event to it's corresponding hook
    channel.on(refEvent, filter: ChannelFilter()) { [weak self] message in
      self?.cancelTimeout()
      self?.mutableState.withValue {
        $0.cancelRefEvent()
        $0.receivedMessage = message
      }

      /// Check if there is event a status available
      guard let status = message.status else { return }
      self?.matchReceive(status, message: message)
    }

    let timeout = mutableState.timeout

    let timeoutTask = Task {
      try? await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(timeout))
      self.trigger(.timeout, payload: [:])
    }

    mutableState.withValue {
      $0.timeoutTask = timeoutTask
    }
  }

  /// Checks if a status has already been received by the Push.
  ///
  /// - parameter status: Status to check
  /// - return: True if given status has been received by the Push.
  func hasReceived(status: PushStatus) -> Bool {
    mutableState.receivedMessage?.status == status
  }

  /// Triggers an event to be sent though the Channel
  func trigger(_ status: PushStatus, payload: Payload) {
    /// If there is no ref event, then there is nothing to trigger on the channel
    guard let refEvent = mutableState.refEvent else { return }

    var mutPayload = payload
    mutPayload["status"] = .string(status.rawValue)

    mutableState.channel?.trigger(event: refEvent, payload: mutPayload)
  }
}
