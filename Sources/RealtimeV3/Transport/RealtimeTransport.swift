//
//  RealtimeTransport.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 27/06/26.
//

import Foundation

/// A frame sent or received over a Realtime transport connection.
///
/// A `TransportFrame` represents the low-level unit of communication between the client and server.
/// It can be either a text frame (containing a UTF-8 encoded string) or a binary frame (containing raw bytes).
public enum TransportFrame: Sendable, Equatable {
  /// A text frame containing a UTF-8 encoded string payload.
  case text(String)
  /// A binary frame containing raw bytes.
  case binary(Data)
}

/// A protocol for establishing Realtime connections over a transport layer.
///
/// `RealtimeTransport` abstracts the underlying connection mechanism (e.g., WebSocket)
/// and provides a unified interface for creating connections to a Realtime endpoint.
/// Implementations should handle authentication via the provided headers and manage
/// the underlying socket lifecycle.
public protocol RealtimeTransport: Sendable {
  /// Establishes a connection to the specified Realtime endpoint.
  ///
  /// This method returns once the underlying connection is established and ready to send/receive frames.
  /// The provided headers are sent as part of the connection handshake (e.g., WebSocket upgrade headers)
  /// and may include authentication credentials or custom metadata.
  ///
  /// - Parameters:
  ///   - url: The Realtime endpoint URL to connect to.
  ///   - headers: HTTP headers to send during the connection handshake.
  ///
  /// - Returns: A ``RealtimeConnection`` object that can be used to send frames and receive frames.
  ///
  /// - Throws: An error if the connection fails (e.g., network error, authentication failure,
  ///   or if the server closes the connection during handshake).
  func connect(to url: URL, headers: [String: String]) async throws -> any RealtimeConnection
}

/// A protocol representing an active connection to a Realtime endpoint.
///
/// Once established via ``RealtimeTransport/connect(to:headers:)``, a `RealtimeConnection`
/// provides a bidirectional communication channel: the SDK consumes the ``frames`` stream
/// to receive frames from the server, and uses ``send(_:)`` to transmit frames to the server.
///
/// The `frames` stream is **single-consumer**: only one iterator should be created and owned
/// by the SDK's connection manager. The iterator remains active until the connection is closed
/// or an error occurs on the underlying transport.
public protocol RealtimeConnection: Sendable {
  /// An asynchronous stream of frames received from the server.
  ///
  /// This stream is single-consumer and should be owned and iterated by the SDK's connection owner.
  /// Once an iterator is created, it remains active until:
  /// - A frame is received indicating server-initiated close
  /// - An error is thrown (e.g., connection lost)
  /// - The connection is explicitly closed via ``close(code:reason:)``
  /// - The iterator is deallocated
  ///
  /// The stream yields ``TransportFrame`` values as they arrive from the server.
  var frames: AsyncThrowingStream<TransportFrame, any Error & Sendable> { get }

  /// Sends a frame to the server.
  ///
  /// This method asynchronously sends the provided frame and returns once the frame
  /// has been queued for transmission (not necessarily fully delivered to the network).
  ///
  /// - Parameter frame: The ``TransportFrame`` to send.
  ///
  /// - Throws: An error if the connection is closed or if the underlying transport
  ///   encounters an error during transmission.
  func send(_ frame: TransportFrame) async throws

  /// Closes the connection with an optional code and reason.
  ///
  /// This method initiates a graceful close of the connection and awaits its completion.
  /// After this method returns, the underlying connection is fully closed and no further
  /// frames can be sent. The ``frames`` stream may emit additional frames before closing,
  /// depending on the underlying protocol behavior.
  ///
  /// - Parameters:
  ///   - code: An optional close code (e.g., 1000 for normal closure in WebSocket).
  ///   - reason: An optional human-readable reason for closing.
  func close(code: Int, reason: String) async
}
