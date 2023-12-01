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
@_spi(Internal) import _Helpers
import ConcurrencyExtras

public enum SocketError: Error {
  case abnormalClosureError
}

/// Alias for a JSON dictionary [String: Any]
public typealias Payload = [String: AnyJSON]

/// Struct that gathers callbacks assigned to the Socket
struct StateChangeCallbacks {
  var open: [(ref: String, callback: @MainActor @Sendable (URLResponse?) -> Void)] = []
  var close: [(ref: String, callback: @MainActor @Sendable (Int, String?) -> Void)] = []
  var error: [(ref: String, callback: @MainActor @Sendable (Error, URLResponse?) -> Void)] = []
  var message: [(ref: String, callback: @MainActor @Sendable (Message) -> Void)] = []
}

/// ## Socket Connection
/// A single connection is established to the server and
/// channels are multiplexed over the connection.
/// Connect to the server using the `RealtimeClient` class:
///
/// ```swift
/// let socket = new RealtimeClient("/socket", paramsClosure: { ["userToken": "123" ] })
/// socket.connect()
/// ```
///
/// The `RealtimeClient` constructor takes the mount point of the socket,
/// the authentication params, as well as options that can be found in
/// the Socket docs, such as configuring the heartbeat.
public final class RealtimeClient: @unchecked Sendable, PhoenixTransportDelegate {
  struct MutableState {
    /// The fully qualified socket URL
    var endpointURL: URL
    var params: Payload

    /// Disables heartbeats from being sent. Default is false.
    var skipHeartbeat: Bool = false

    /// Callbacks for socket state changes
    var stateChangeCallbacks: StateChangeCallbacks = .init()

    /// Ref counter for messages
    var ref: UInt64 = .min // 0 (max: 18,446,744,073,709,551,615)

    /// Collection on channels created for the Socket
    var channels: [RealtimeChannel] = []

    /// Buffers messages that need to be sent once the socket has connected. It is an array
    /// of tuples, with the ref of the message to send and the callback that will send the message.
    var sendBuffer: [(ref: String?, callback: () -> Void)] = []

    /// Timer that triggers sending new Heartbeat messages
    var heartbeatTimer: HeartbeatTimerProtocol?

    /// Ref counter for the last heartbeat that was sent
    var pendingHeartbeatRef: String?

    /// Close status
    var closeStatus: CloseStatus = .unknown

    /// The connection to the server
    var connection: PhoenixTransport? = nil

    var accessToken: String?

    mutating func append<T>(
      callback: T,
      to array: WritableKeyPath<MutableState, [(ref: String, callback: T)]>
    ) -> String {
      let ref = makeRef()
      self[keyPath: array].append((ref, callback))
      return ref
    }

    /// - return: the next message ref, accounting for overflows
    mutating func makeRef() -> String {
      ref = (ref == UInt64.max) ? 0 : ref + 1
      return String(ref)
    }

    mutating func releaseCallbacks() {
      stateChangeCallbacks = .init()
    }

    mutating func releaseCallbacks(referencedBy refs: [String]) {
      stateChangeCallbacks.open = stateChangeCallbacks.open.filter {
        !refs.contains($0.ref)
      }

      stateChangeCallbacks.close = stateChangeCallbacks.close.filter {
        !refs.contains($0.ref)
      }

      stateChangeCallbacks.error = stateChangeCallbacks.error.filter {
        !refs.contains($0.ref)
      }

      stateChangeCallbacks.message = stateChangeCallbacks.message.filter {
        !refs.contains($0.ref)
      }
    }

    /// Removes an item from the sendBuffer with the matching ref
    mutating func removeFromSendBuffer(ref: String) {
      sendBuffer = sendBuffer.filter { $0.ref != ref }
    }
  }

  private let mutableState: LockIsolated<MutableState>

  // ----------------------------------------------------------------------

  // MARK: - Public Attributes

  // ----------------------------------------------------------------------
  /// The string WebSocket endpoint (ie `"ws://example.com/socket"`,
  /// `"wss://example.com"`, etc.) That was passed to the Socket during
  /// initialization. The URL endpoint will be modified by the Socket to
  /// include `"/websocket"` if missing.
  public let url: URL

  /// The fully qualified socket URL
  public var endpointURL: URL {
    mutableState.endpointURL
  }

  public var params: Payload {
    get { mutableState.params }
    set { mutableState.withValue { $0.params = newValue } }
  }

  /// The WebSocket transport. Default behavior is to provide a
  /// URLSessionWebSocketTask. See README for alternatives.
  let transport: @Sendable (URL) -> PhoenixTransport

  /// Phoenix serializer version, defaults to "2.0.0"
  public let vsn: String

  /// Override to provide custom encoding of data before writing to the socket
  public let encode: (Any) -> Data = Defaults.encode

  /// Override to provide custom decoding of data read from the socket
  public let decode: (Data) -> Any? = Defaults.decode

  /// Timeout to use when opening connections
  public var timeout: TimeInterval = Defaults.timeoutInterval

  /// Custom headers to be added to the socket connection request
  public let headers: [String: String]

  /// Interval between sending a heartbeat
  public let heartbeatInterval: TimeInterval = Defaults.heartbeatInterval

  /// Interval between socket reconnect attempts, in seconds
  public let reconnectAfter: (Int) -> TimeInterval = Defaults.reconnectSteppedBackOff

  /// Interval between channel rejoin attempts, in seconds
  public let rejoinAfter: (Int) -> TimeInterval = Defaults.rejoinSteppedBackOff

  /// The optional function to receive logs
  // TODO: move logger to MutableState
  public var logger: ((String) -> Void)?

  /// Disables heartbeats from being sent. Default is false.
  public var skipHeartbeat: Bool {
    get { mutableState.skipHeartbeat }
    set { mutableState.withValue { $0.skipHeartbeat = newValue } }
  }

  // ----------------------------------------------------------------------

  // MARK: - Private Attributes

  // ----------------------------------------------------------------------

  /// Collection on channels created for the Socket
  public var channels: [RealtimeChannel] {
    mutableState.channels
  }

  /// Timer to use when attempting to reconnect
  let reconnectTimer: TimeoutTimerProtocol

  /// The HTTPClient to perform HTTP requests.
  let http: HTTPClient

  var accessToken: String? {
    mutableState.accessToken
  }

  var closeStatus: CloseStatus {
    mutableState.closeStatus
  }

  var connection: PhoenixTransport? {
    mutableState.connection
  }

  public convenience init(
    url: URL,
    headers: [String: String] = [:],
    params: Payload = [:],
    vsn: String = Defaults.vsn
  ) {
    self.init(
      url: url,
      headers: headers,
      transport: { url in URLSessionTransport(url: url) },
      params: params,
      vsn: vsn
    )
  }

  public init(
    url: URL,
    headers: [String: String] = [:],
    transport: @escaping @Sendable (URL) -> PhoenixTransport,
    params: Payload = [:],
    vsn: String = Defaults.vsn
  ) {
    self.transport = transport
    self.url = url
    self.vsn = vsn

    var headers = headers
    if headers["X-Client-Info"] == nil {
      headers["X-Client-Info"] = "realtime-swift/\(version)"
    }
    self.headers = headers
    http = HTTPClient(fetchHandler: { try await URLSession.shared.data(for: $0) })

    let accessToken: String?

    if let jwt = params["Authorization"]?.stringValue?.split(separator: " ").last {
      accessToken = String(jwt)
    } else {
      accessToken = params["apikey"]?.stringValue
    }
    let endpointURL = RealtimeClient.buildEndpointUrl(
      url: url,
      params: params,
      vsn: vsn
    )

    mutableState = LockIsolated(
      MutableState(
        endpointURL: endpointURL,
        params: params,
        accessToken: accessToken
      )
    )

    reconnectTimer = Dependencies.makeTimeoutTimer()
    reconnectTimer.setHandler { [weak self] in
      self?.logItems("Socket attempting to reconnect")
      self?.teardown(reason: "reconnection")
      self?.connect()
    }

    reconnectTimer.setTimerCalculation { [weak self] tries in
      let interval = self?.reconnectAfter(tries) ?? 5.0
      self?.logItems("Socket reconnecting in \(interval)s")
      return interval
    }
  }

  // ----------------------------------------------------------------------

  // MARK: - Public

  // ----------------------------------------------------------------------
  /// - return: The socket protocol, wss or ws
  public var websocketProtocol: String {
    switch endpointURL.scheme {
    case "https": return "wss"
    case "http": return "ws"
    default: return endpointURL.scheme ?? ""
    }
  }

  /// - return: True if the socket is connected
  public var isConnected: Bool {
    connectionState == .open
  }

  /// - return: The state of the connect. [.connecting, .open, .closing, .closed]
  public var connectionState: PhoenixTransportReadyState {
    mutableState.connection?.readyState ?? .closed
  }

  /// Sets the JWT access token used for channel subscription authorization and Realtime RLS.
  /// - Parameter token: A JWT string.
  public func setAuth(_ token: String?) {
    mutableState.withValue {
      $0.accessToken = token
    }

    for channel in channels {
      channel.params["user_token"] = token.map(AnyJSON.string) ?? .null

      if channel.joinedOnce, channel.isJoined {
        channel.push(
          ChannelEvent.accessToken,
          payload: ["access_token": token.map(AnyJSON.string) ?? .null]
        )
      }
    }
  }

  /// Connects the Socket. The params passed to the Socket on initialization
  /// will be sent through the connection. If the Socket is already connected,
  /// then this call will be ignored.
  public func connect() {
    // Do not attempt to reconnect if the socket is currently connected
    guard !isConnected else { return }

    // Reset the close status when attempting to connect
    mutableState.withValue {
      $0.closeStatus = .unknown
      $0.connection = transport(endpointURL)
      $0.connection?.delegate = self

      $0.connection?.connect(with: headers)
    }
  }

  /// Disconnects the socket
  ///
  /// - parameter code: Optional. Closing status code
  /// - parameter callback: Optional. Called when disconnected
  public func disconnect(
    code: CloseCode = CloseCode.normal,
    reason: String? = nil
  ) {
    // The socket was closed cleanly by the User
    mutableState.withValue {
      $0.closeStatus = CloseStatus(closeCode: code.rawValue)
    }

    // Reset any reconnects and teardown the socket connection
    reconnectTimer.reset()
    teardown(code: code, reason: reason)
  }

  func teardown(
    code: CloseCode = CloseCode.normal,
    reason: String? = nil
  ) {
    mutableState.withValue {
      $0.connection?.delegate = nil
      $0.connection?.disconnect(code: code.rawValue, reason: reason)
      $0.connection = nil
    }

    // The socket connection has been turndown, heartbeats are not needed
    mutableState.heartbeatTimer?.stop()

    // Since the connection's delegate was nil'd out, inform all state
    // callbacks that the connection has closed
    Task {
      for (_, callback) in mutableState.stateChangeCallbacks.close {
        await callback(code.rawValue, reason)
      }
    }
  }

  // ----------------------------------------------------------------------

  // MARK: - Register Socket State Callbacks

  // ----------------------------------------------------------------------

  /// Registers callbacks for connection open events. Does not handle retain
  /// cycles. Use `delegateOnOpen(to:)` for automatic handling of retain cycles.
  ///
  /// Example:
  ///
  ///     socket.onOpen() { [weak self] in
  ///         self?.print("Socket Connection Open")
  ///     }
  ///
  /// - parameter callback: Called when the Socket is opened
  @discardableResult
  public func onOpen(callback: @MainActor @escaping @Sendable () -> Void) -> String {
    onOpen { _ in callback() }
  }

  /// Registers callbacks for connection open events. Does not handle retain
  /// cycles. Use `delegateOnOpen(to:)` for automatic handling of retain cycles.
  ///
  /// Example:
  ///
  ///     socket.onOpen() { [weak self] response in
  ///         self?.print("Socket Connection Open")
  ///     }
  ///
  /// - parameter callback: Called when the Socket is opened
  @discardableResult
  public func onOpen(callback: @MainActor @escaping @Sendable (URLResponse?) -> Void) -> String {
    mutableState.withValue {
      $0.append(callback: callback, to: \.stateChangeCallbacks.open)
    }
  }

  /// Registers callbacks for connection close events. Does not handle retain
  /// cycles. Use `delegateOnClose(_:)` for automatic handling of retain cycles.
  ///
  /// Example:
  ///
  ///     socket.onClose() { [weak self] in
  ///         self?.print("Socket Connection Close")
  ///     }
  ///
  /// - parameter callback: Called when the Socket is closed
  @discardableResult
  public func onClose(callback: @MainActor @escaping @Sendable () -> Void) -> String {
    onClose { _, _ in callback() }
  }

  /// Registers callbacks for connection close events. Does not handle retain
  /// cycles. Use `delegateOnClose(_:)` for automatic handling of retain cycles.
  ///
  /// Example:
  ///
  ///     socket.onClose() { [weak self] code, reason in
  ///         self?.print("Socket Connection Close")
  ///     }
  ///
  /// - parameter callback: Called when the Socket is closed
  @discardableResult
  public func onClose(callback: @MainActor @escaping @Sendable (Int, String?) -> Void) -> String {
    mutableState.withValue {
      $0.append(callback: callback, to: \.stateChangeCallbacks.close)
    }
  }

  /// Registers callbacks for connection error events. Does not handle retain
  /// cycles. Use `delegateOnError(to:)` for automatic handling of retain cycles.
  ///
  /// Example:
  ///
  ///     socket.onError() { [weak self] (error) in
  ///         self?.print("Socket Connection Error", error)
  ///     }
  ///
  /// - parameter callback: Called when the Socket errors
  @discardableResult
  public func onError(callback: @MainActor @escaping @Sendable (Error, URLResponse?) -> Void)
    -> String
  {
    mutableState.withValue {
      $0.append(callback: callback, to: \.stateChangeCallbacks.error)
    }
  }

  /// Registers callbacks for connection message events. Does not handle
  /// retain cycles. Use `delegateOnMessage(_to:)` for automatic handling of
  /// retain cycles.
  ///
  /// Example:
  ///
  ///     socket.onMessage() { [weak self] (message) in
  ///         self?.print("Socket Connection Message", message)
  ///     }
  ///
  /// - parameter callback: Called when the Socket receives a message event
  @discardableResult
  public func onMessage(callback: @MainActor @escaping @Sendable (Message) -> Void) -> String {
    mutableState.withValue {
      $0.append(callback: callback, to: \.stateChangeCallbacks.message)
    }
  }

  /// Releases all stored callback hooks (onError, onOpen, onClose, etc.) You should
  /// call this method when you are finished when the Socket in order to release
  /// any references held by the socket.
  public func releaseCallbacks() {
    mutableState.withValue { $0.releaseCallbacks() }
  }

  // ----------------------------------------------------------------------

  // MARK: - Channel Initialization

  // ----------------------------------------------------------------------
  /// Initialize a new Channel
  ///
  /// Example:
  ///
  ///     let channel = socket.channel("rooms", params: ["user_id": "abc123"])
  ///
  /// - parameter topic: Topic of the channel
  /// - parameter params: Optional. Parameters for the channel
  /// - return: A new channel
  public func channel(
    _ topic: String,
    params: RealtimeChannelOptions = .init()
  ) -> RealtimeChannel {
    let channel = RealtimeChannel(
      topic: "realtime:\(topic)", params: params.params, socket: self
    )

    mutableState.withValue {
      $0.channels.append(channel)
    }

    return channel
  }

  /// Unsubscribes and removes a single channel
  public func remove(_ channel: RealtimeChannel) {
    channel.unsubscribe()
    off(channel.stateChangeRefs)

    mutableState.withValue {
      $0.channels.removeAll(where: { $0.joinRef == channel.joinRef })
    }

    if channels.isEmpty {
      disconnect()
    }
  }

  /// Unsubscribes and removes all channels
  public func removeAllChannels() async {
    for channel in channels {
      remove(channel)
    }
  }

  /// Removes `onOpen`, `onClose`, `onError,` and `onMessage` registrations.
  ///
  ///
  /// - Parameter refs: List of refs returned by calls to `onOpen`, `onClose`, etc
  public func off(_ refs: [String]) {
    mutableState.withValue {
      $0.releaseCallbacks(referencedBy: refs)
    }
  }

  // ----------------------------------------------------------------------

  // MARK: - Sending Data

  // ----------------------------------------------------------------------
  /// Sends data through the Socket. This method is internal. Instead, you
  /// should call `push(_:, payload:, timeout:)` on the Channel you are
  /// sending an event to.
  ///
  /// - parameter topic:
  /// - parameter event:
  /// - parameter payload:
  /// - parameter ref: Optional. Defaults to nil
  /// - parameter joinRef: Optional. Defaults to nil
  func push(message: Message) {
    let callback: (() -> Void) = { [weak self] in
      guard let self else { return }
      do {
        let data = try JSONEncoder().encode(message)

        self.logItems(
          "push",
          "Sending \(String(data: data, encoding: String.Encoding.utf8) ?? "")"
        )
        self.mutableState.connection?.send(data: data)
      } catch {
        // TODO: handle error
      }
    }

    /// If the socket is connected, then execute the callback immediately.
    if isConnected {
      callback()
    } else {
      /// If the socket is not connected, add the push to a buffer which will
      /// be sent immediately upon connection.
      mutableState.withValue {
        $0.sendBuffer.append((ref: message.ref, callback: callback))
      }
    }
  }

  /// Logs the message. Override Socket.logger for specialized logging. noops by default
  ///
  /// - parameter items: List of items to be logged. Behaves just like debugPrint()
  func logItems(_ items: Any...) {
    let msg = items.map { String(describing: $0) }.joined(separator: ", ")
    logger?("SwiftPhoenixClient: \(msg)")
  }

  // ----------------------------------------------------------------------

  // MARK: - Connection Events

  // ----------------------------------------------------------------------
  /// Called when the underlying Websocket connects to it's host
  func onConnectionOpen(response: URLResponse?) {
    logItems("transport", "Connected to \(url)")

    // Reset the close status now that the socket has been connected
    mutableState.withValue {
      $0.closeStatus = .unknown
    }

    // Send any messages that were waiting for a connection
    flushSendBuffer()

    // Reset how the socket tried to reconnect
    reconnectTimer.reset()

    // Restart the heartbeat timer
    resetHeartbeat()

    Task {
      // Inform all onOpen callbacks that the Socket has opened
      for (_, callback) in mutableState.stateChangeCallbacks.open {
        await callback(response)
      }
    }
  }

  func onConnectionClosed(code: Int, reason: String?) {
    logItems("transport", "close")

    // Send an error to all channels
    triggerChannelError()

    // Prevent the heartbeat from triggering if the
    mutableState.heartbeatTimer?.stop()

    // Only attempt to reconnect if the socket did not close normally,
    // or if it was closed abnormally but on client side (e.g. due to heartbeat timeout)
    if mutableState.closeStatus.shouldReconnect {
      reconnectTimer.scheduleTimeout()
    }

    Task {
      for (_, callback) in mutableState.stateChangeCallbacks.close {
        await callback(code, reason)
      }
    }
  }

  func onConnectionError(_ error: Error, response: URLResponse?) {
    logItems("transport", error, response ?? "")

    // Send an error to all channels
    triggerChannelError()

    Task {
      // Inform any state callbacks of the error
      for (_, callback) in mutableState.stateChangeCallbacks.error {
        await callback(error, response)
      }
    }
  }

  func onConnectionMessage(_ message: Data) {
    let rawMessage = String(data: message, encoding: .utf8) ?? ""
    logItems("receive ", rawMessage)

    do {
      let message = try JSONDecoder().decode(Message.self, from: message)

      // Clear heartbeat ref, preventing a heartbeat timeout disconnect
      mutableState.withValue {
        if message.ref == $0.pendingHeartbeatRef {
          $0.pendingHeartbeatRef = nil
        }
      }

      if message.event == "phx_close" {
        print("Close Event Received")
      }

      // Dispatch the message to all channels that belong to the topic
      for channel in channels.filter({ $0.isMember(message) }) {
        channel.trigger(message)
      }

      Task {
        // Inform all onMessage callbacks of the message
        for (_, callback) in mutableState.stateChangeCallbacks.message {
          await callback(message)
        }
      }
    } catch {
      logItems("receive: Unable to parse JSON: \(rawMessage) error: \(error)")
      return
    }
  }

  /// Triggers an error event to all of the connected Channels
  func triggerChannelError() {
    for channel in channels {
      // Only trigger a channel error if it is in an "opened" state
      if !(channel.isErrored || channel.isLeaving || channel.isClosed) {
        channel.trigger(event: ChannelEvent.error)
      }
    }
  }

  /// Send all messages that were buffered before the socket opened
  func flushSendBuffer() {
    mutableState.withValue {
      guard isConnected, $0.sendBuffer.count > 0 else { return }
      $0.sendBuffer.forEach { $0.callback() }
      $0.sendBuffer = []
    }
  }

  func makeRef() -> String {
    mutableState.withValue { $0.makeRef() }
  }

  func removeFromSendBuffer(ref: String) {
    mutableState.withValue { $0.removeFromSendBuffer(ref: ref) }
  }

  /// Builds a fully qualified socket `URL` from `endPoint` and `params`.
  static func buildEndpointUrl(
    url: URL,
    params: [String: Any],
    vsn: String
  ) -> URL {
    guard var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { fatalError("Malformed URL: \(url)") }

    // Ensure that the URL ends with "/websocket
    if !urlComponents.path.contains("/websocket") {
      // Do not duplicate '/' in the path
      if urlComponents.path.last != "/" {
        urlComponents.path.append("/")
      }

      // append 'websocket' to the path
      urlComponents.path.append("websocket")
    }

    urlComponents.queryItems = [URLQueryItem(name: "vsn", value: vsn)]

    // If there are parameters, append them to the URL
    if !params.isEmpty {
      urlComponents.queryItems?.append(
        contentsOf: params.map {
          URLQueryItem(name: $0.key, value: String(describing: $0.value))
        }
      )
    }

    guard let qualifiedUrl = urlComponents.url
    else { fatalError("Malformed URL while adding parameters") }
    return qualifiedUrl
  }

  // Leaves any channel that is open that has a duplicate topic
  func leaveOpenTopic(topic: String) {
    guard
      let dupe = channels.first(where: { $0.topic == topic && ($0.isJoined || $0.isJoining) })
    else { return }

    logItems("transport", "leaving duplicate topic: [\(topic)]")
    dupe.unsubscribe()
  }

  // ----------------------------------------------------------------------

  // MARK: - Heartbeat

  // ----------------------------------------------------------------------
  func resetHeartbeat() {
    // Clear anything related to the heartbeat
    mutableState.withValue {
      $0.pendingHeartbeatRef = nil
    }

    mutableState.heartbeatTimer?.stop()

    // Do not start up the heartbeat timer if skipHeartbeat is true
    guard !skipHeartbeat else { return }

    let heartbeatTimer = Dependencies.makeHeartbeatTimer(
      heartbeatInterval,
      Defaults.heartbeatLeeway
    )
    mutableState.withValue { $0.heartbeatTimer = heartbeatTimer }

    heartbeatTimer.start { [weak self] in
      self?.sendHeartbeat()
    }
  }

  /// Sends a heartbeat payload to the phoenix servers
  func sendHeartbeat() {
    // Do not send if the connection is closed
    guard isConnected else { return }

    // If there is a pending heartbeat ref, then the last heartbeat was
    // never acknowledged by the server. Close the connection and attempt
    // to reconnect.

    let pendingHeartbeatRef: String? = mutableState.withValue {
      if $0.pendingHeartbeatRef != nil {
        $0.pendingHeartbeatRef = nil

        logItems(
          "transport",
          "heartbeat timeout. Attempting to re-establish connection"
        )

        // Close the socket manually, flagging the closure as abnormal. Do not use
        // `teardown` or `disconnect` as they will nil out the websocket delegate.
        abnormalClose("heartbeat timeout")
        return nil
      } else {
        // The last heartbeat was acknowledged by the server. Send another one
        $0.pendingHeartbeatRef = $0.makeRef()
        return $0.pendingHeartbeatRef
      }
    }

    if let pendingHeartbeatRef {
      push(
        message: Message(
          ref: pendingHeartbeatRef,
          topic: "phoenix",
          event: ChannelEvent.heartbeat,
          payload: [:]
        )
      )
    }
  }

  func abnormalClose(_ reason: String) {
    mutableState.withValue {
      $0.closeStatus = .abnormal

      /*
       We use NORMAL here since the client is the one determining to close the
       connection. However, we set to close status to abnormal so that
       the client knows that it should attempt to reconnect.

       If the server subsequently acknowledges with code 1000 (normal close),
       the socket will keep the `.abnormal` close status and trigger a reconnection.
       */
      $0.connection?.disconnect(code: CloseCode.normal.rawValue, reason: reason)
    }
  }

  // ----------------------------------------------------------------------

  // MARK: - TransportDelegate

  // ----------------------------------------------------------------------
  public func onOpen(response: URLResponse?) {
    onConnectionOpen(response: response)
  }

  public func onError(error: Error, response: URLResponse?) {
    onConnectionError(error, response: response)
  }

  public func onMessage(message: Data) {
    onConnectionMessage(message)
  }

  public func onClose(code: Int, reason: String? = nil) {
    mutableState.withValue {
      $0.closeStatus.update(transportCloseCode: code)
    }
    onConnectionClosed(code: code, reason: reason)
  }
}

// ----------------------------------------------------------------------

// MARK: - Close Codes

// ----------------------------------------------------------------------
extension RealtimeClient {
  public enum CloseCode: Int {
    case abnormal = 999

    case normal = 1000

    case goingAway = 1001
  }
}

// ----------------------------------------------------------------------

// MARK: - Close Status

// ----------------------------------------------------------------------
extension RealtimeClient {
  /// Indicates the different closure states a socket can be in.
  enum CloseStatus: Equatable {
    /// Undetermined closure state
    case unknown
    /// A clean closure requested either by the client or the server
    case clean
    /// An abnormal closure requested by the client
    case abnormal

    /// Temporarily close the socket, pausing reconnect attempts. Useful on mobile
    /// clients when disconnecting a because the app resigned active but should
    /// reconnect when app enters active state.
    case temporary

    init(closeCode: Int) {
      switch closeCode {
      case CloseCode.abnormal.rawValue:
        self = .abnormal
      case CloseCode.goingAway.rawValue:
        self = .temporary
      default:
        self = .clean
      }
    }

    mutating func update(transportCloseCode: Int) {
      switch self {
      case .unknown, .clean, .temporary:
        // Allow transport layer to override these statuses.
        self = .init(closeCode: transportCloseCode)
      case .abnormal:
        // Do not allow transport layer to override the abnormal close status.
        // The socket itself should reset it on the next connection attempt.
        // See `Socket.abnormalClose(_:)` for more information.
        break
      }
    }

    var shouldReconnect: Bool {
      switch self {
      case .unknown, .abnormal:
        return true
      case .clean, .temporary:
        return false
      }
    }
  }
}
