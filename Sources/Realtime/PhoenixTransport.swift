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

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// ----------------------------------------------------------------------

// MARK: - Transport Protocol

// ----------------------------------------------------------------------
/**
 Defines a `Socket`'s Transport layer.
 */
// sourcery: AutoMockable
public protocol PhoenixTransport {
  /// The current `ReadyState` of the `Transport` layer
  var readyState: PhoenixTransportReadyState { get }

  /// Delegate for the `Transport` layer
  var delegate: PhoenixTransportDelegate? { get set }

  /**
   Connect to the server

   - Parameters:
   - headers: Headers to include in the URLRequests when opening the Websocket connection. Can be empty [:]
   */
  func connect(with headers: [String: String])

  /**
   Disconnect from the server.

   - Parameters:
   - code: Status code as defined by <ahref="http://tools.ietf.org/html/rfc6455#section-7.4">Section 7.4 of RFC 6455</a>.
   - reason: Reason why the connection is closing. Optional.
   */
  func disconnect(code: Int, reason: String?)

  /**
   Sends a message to the server.

   - Parameter data: Data to send.
   */
  func send(data: Data)
}

// ----------------------------------------------------------------------

// MARK: - Transport Delegate Protocol

// ----------------------------------------------------------------------
/// Delegate to receive notifications of events that occur in the `Transport` layer
public protocol PhoenixTransportDelegate {
  /**
   Notified when the `Transport` opens.

   - Parameter response: Response from the server indicating that the WebSocket handshake was successful and the connection has been upgraded to webSockets
   */
  func onOpen(response: URLResponse?)

  /**
   Notified when the `Transport` receives an error.

   - Parameter error: Client-side error from the underlying `Transport` implementation
   - Parameter response: Response from the server, if any, that occurred with the Error

   */
  func onError(error: Error, response: URLResponse?)

  /**
   Notified when the `Transport` receives a message from the server.

   - Parameter message: Message received from the server
   */
  func onMessage(message: String)

  /**
   Notified when the `Transport` closes.

   - Parameter code: Code that was sent when the `Transport` closed
   - Parameter reason: A concise human-readable prose explanation for the closure
   */
  func onClose(code: Int, reason: String?)
}

// ----------------------------------------------------------------------

// MARK: - Transport Ready State Enum

// ----------------------------------------------------------------------
/// Available `ReadyState`s of a `Transport` layer.
public enum PhoenixTransportReadyState {
  /// The `Transport` is opening a connection to the server.
  case connecting

  /// The `Transport` is connected to the server.
  case open

  /// The `Transport` is closing the connection to the server.
  case closing

  /// The `Transport` has disconnected from the server.
  case closed
}

// ----------------------------------------------------------------------

// MARK: - Default Websocket Transport Implementation

// ----------------------------------------------------------------------
/// A `Transport` implementation that relies on URLSession's native WebSocket
/// implementation.
///
/// This implementation ships default with SwiftPhoenixClient however
/// SwiftPhoenixClient supports earlier OS versions using one of the submodule
/// `Transport` implementations. Or you can create your own implementation using
/// your own WebSocket library or implementation.
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
open class URLSessionTransport: NSObject, PhoenixTransport, URLSessionWebSocketDelegate {
  /// The URL to connect to
  let url: URL

  /// The URLSession configuration
  let configuration: URLSessionConfiguration

  /// The underling URLSession. Assigned during `connect()`
  private var session: URLSession? = nil

  /// The ongoing task. Assigned during `connect()`
  private var task: URLSessionWebSocketTask? = nil

  /**
   Initializes a `Transport` layer built using URLSession's WebSocket

   Example:

   ```swift
   let url = URL("wss://example.com/socket")
   let transport: Transport = URLSessionTransport(url: url)
   ```

   Using a custom `URLSessionConfiguration`

   ```swift
   let url = URL("wss://example.com/socket")
   let configuration = URLSessionConfiguration.default
   let transport: Transport = URLSessionTransport(url: url, configuration: configuration)
   ```

   - parameter url: URL to connect to
   - parameter configuration: Provide your own URLSessionConfiguration. Uses `.default` if none provided
   */
  public init(url: URL, configuration: URLSessionConfiguration = .default) {
    // URLSession requires that the endpoint be "wss" instead of "https".
    let endpoint = url.absoluteString
    let wsEndpoint =
      endpoint
        .replacingOccurrences(of: "http://", with: "ws://")
        .replacingOccurrences(of: "https://", with: "wss://")

    // Force unwrapping should be safe here since a valid URL came in and we just
    // replaced the protocol.
    self.url = URL(string: wsEndpoint)!
    self.configuration = configuration

    super.init()
  }

  // MARK: - Transport

  public var readyState: PhoenixTransportReadyState = .closed
  public var delegate: PhoenixTransportDelegate? = nil

  public func connect(with headers: [String: String]) {
    // Set the transport state as connecting
    readyState = .connecting

    // Create the session and websocket task
    session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    var request = URLRequest(url: url)

    headers.forEach { (key: String, value: Any) in
      guard let value = value as? String else { return }
      request.addValue(value, forHTTPHeaderField: key)
    }

    task = session?.webSocketTask(with: request)

    // Start the task
    task?.resume()
  }

  open func disconnect(code: Int, reason: String?) {
    /*
     TODO:
     1. Provide a "strict" mode that fails if an invalid close code is given
     2. If strict mode is disabled, default to CloseCode.invalid
     3. Provide default .normalClosure function
     */
    guard let closeCode = URLSessionWebSocketTask.CloseCode(rawValue: code) else {
      fatalError("Could not create a CloseCode with invalid code: [\(code)].")
    }

    readyState = .closing
    task?.cancel(with: closeCode, reason: reason?.data(using: .utf8))
    session?.finishTasksAndInvalidate()
  }

  open func send(data: Data) {
    #if os(Linux) || os(Windows)
    Task {
      try? await task?.send(.string(String(data: data, encoding: .utf8)!))
    }
    #else
    task?.send(.string(String(data: data, encoding: .utf8)!)) { _ in
      // TODO: What is the behavior when an error occurs?
    }
    #endif
  }

  // MARK: - URLSessionWebSocketDelegate

  open func urlSession(
    _: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didOpenWithProtocol _: String?
  ) {
    // The Websocket is connected. Set Transport state to open and inform delegate
    readyState = .open
    delegate?.onOpen(response: webSocketTask.response)

    // Start receiving messages
    receive()
  }

  open func urlSession(
    _: URLSession,
    webSocketTask _: URLSessionWebSocketTask,
    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
    reason: Data?
  ) {
    // A close frame was received from the server.
    readyState = .closed
    delegate?.onClose(
      code: closeCode.rawValue, reason: reason.flatMap { String(data: $0, encoding: .utf8) }
    )
  }

  open func urlSession(
    _: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    // The task has terminated. Inform the delegate that the transport has closed abnormally
    // if this was caused by an error.
    guard let err = error else { return }

    abnormalErrorReceived(err, response: task.response)
  }

  // MARK: - Private

  private func receive() {
    #if os(Linux) || os(Windows)
    Task {
      do {
        let result = try await task?.receive()
        switch result {
        case .data:
          print("Data received. This method is unsupported by the Client")
        case let .string(text):
          self.delegate?.onMessage(message: text)
        default:
          fatalError("Unknown result was received. [\(result)]")
        }

        // Since `.receive()` is only good for a single message, it must
        // be called again after a message is received in order to
        // received the next message.
        self.receive()
      } catch {
        print("Error when receiving \(error)")
        self.abnormalErrorReceived(error, response: nil)
      }
    }
    #else
    task?.receive { [weak self] result in
      switch result {
      case let .success(message):
        switch message {
        case .data:
          print("Data received. This method is unsupported by the Client")
        case let .string(text):
          self?.delegate?.onMessage(message: text)
        default:
          fatalError("Unknown result was received. [\(result)]")
        }

        // Since `.receive()` is only good for a single message, it must
        // be called again after a message is received in order to
        // received the next message.
        self?.receive()
      case let .failure(error):
        print("Error when receiving \(error)")
        self?.abnormalErrorReceived(error, response: nil)
      }
    }
    #endif
  }

  private func abnormalErrorReceived(_ error: Error, response: URLResponse?) {
    // Set the state of the Transport to closed
    readyState = .closed

    // Inform the Transport's delegate that an error occurred.
    delegate?.onError(error: error, response: response)

    // An abnormal error is results in an abnormal closure, such as internet getting dropped
    // so inform the delegate that the Transport has closed abnormally. This will kick off
    // the reconnect logic.
    delegate?.onClose(
      code: RealtimeClient.CloseCode.abnormal.rawValue, reason: error.localizedDescription
    )
  }
}
