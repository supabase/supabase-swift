//
//  LoopbackWebSocketServer.swift
//  Supabase
//
//  Created by Guilherme Souza on 06/10/26.
//

import ConcurrencyExtras
import Foundation

struct LoopbackError: Error {
  let message: String
}

#if canImport(Network)
  import Network

  final class LoopbackWebSocketServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "co.supabase.LoopbackWebSocketServer")
    private var connections: [NWConnection] = []
    private var isStopped = false
    private var received: [Data] = []

    /// Every message the clients sent, in arrival order.
    var receivedMessages: [Data] {
      queue.sync { received }
    }

    /// Sends a close frame with `code` to every connected client.
    func close(code: NWProtocolWebSocket.CloseCode, reason: String) {
      queue.async { [self] in
        let metadata = NWProtocolWebSocket.Metadata(opcode: .close)
        metadata.closeCode = code
        let context = NWConnection.ContentContext(identifier: "close", metadata: [metadata])
        for connection in connections {
          connection.send(
            content: Data(reason.utf8),
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { _ in }
          )
        }
      }
    }

    init() throws {
      let parameters = NWParameters.tcp
      let webSocketOptions = NWProtocolWebSocket.Options()
      webSocketOptions.autoReplyPing = true
      parameters.defaultProtocolStack.applicationProtocols.insert(webSocketOptions, at: 0)
      listener = try NWListener(using: parameters, on: .any)
    }

    func start() throws -> UInt16 {
      let ready = DispatchSemaphore(value: 0)

      listener.stateUpdateHandler = { state in
        if case .ready = state { ready.signal() }
      }

      listener.newConnectionHandler = { [weak self] connection in
        guard let self else { return }
        if self.isStopped {
          connection.cancel()
          return
        }
        self.connections.append(connection)
        connection.start(queue: self.queue)
        self.receive(on: connection)
      }

      listener.start(queue: queue)

      guard ready.wait(timeout: .now() + 5) == .success, let port = listener.port else {
        throw LoopbackError(message: "loopback server failed to start")
      }

      return port.rawValue
    }

    private func receive(on connection: NWConnection) {
      connection.receiveMessage { [weak self] data, context, _, error in
        if let data { self?.received.append(data) }
        if let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
          as? NWProtocolWebSocket.Metadata, metadata.opcode == .close
        {
          let closeMetadata = NWProtocolWebSocket.Metadata(opcode: .close)
          let closeContext = NWConnection.ContentContext(
            identifier: "close", metadata: [closeMetadata])
          connection.send(
            content: nil,
            contentContext: closeContext,
            isComplete: true,
            completion: .contentProcessed { _ in connection.cancel() }
          )
          return
        }

        guard error == nil else { return }
        self?.receive(on: connection)
      }
    }

    /// Pushes a frame from the server to every connected client.
    ///
    /// Every other test here only drives traffic client→server, which is why
    /// `URLSessionWebSocket._handleMessage` had no coverage: nothing ever arrived for it to
    /// handle. Dispatched on `queue` so it is ordered after the `newConnectionHandler` that
    /// appended the connection.
    func send(text: String) {
      send(Data(text.utf8), opcode: .text)
    }

    func send(binary: Data) {
      send(binary, opcode: .binary)
    }

    private func send(_ payload: Data, opcode: NWProtocolWebSocket.Opcode) {
      queue.async { [self] in
        let metadata = NWProtocolWebSocket.Metadata(opcode: opcode)
        let context = NWConnection.ContentContext(identifier: "send", metadata: [metadata])

        for connection in connections {
          connection.send(
            content: payload,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { _ in }
          )
        }
      }
    }

    func stop() {
      queue.sync {
        isStopped = true
        listener.cancel()
        for connection in connections { connection.cancel() }
        connections.removeAll()
      }
    }
  }

  /// A plain TCP listener for handshake failures the WebSocket server cannot produce: it hands
  /// every accepted connection to `handle`, which may answer with raw HTTP or stay silent.
  final class LoopbackTCPServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "co.supabase.LoopbackTCPServer")
    private var connections: [NWConnection] = []
    private let handle: @Sendable (NWConnection) -> Void

    init(handle: @escaping @Sendable (NWConnection) -> Void) throws {
      listener = try NWListener(using: .tcp, on: .any)
      self.handle = handle
    }

    /// Answers every upgrade request with `status` and records the request it received.
    static func refusing(status: Int, reason: String) throws -> (
      LoopbackTCPServer, LockIsolated<String>
    ) {
      let request = LockIsolated("")
      let server = try LoopbackTCPServer { connection in
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, _, _ in
          request.setValue(String(decoding: data ?? Data(), as: UTF8.self))
          let response =
            "HTTP/1.1 \(status) \(reason)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
          connection.send(
            content: Data(response.utf8), isComplete: true,
            completion: .contentProcessed { _ in connection.cancel() })
        }
      }
      return (server, request)
    }

    /// Accepts the TCP connection and never answers the upgrade.
    static func stalling() throws -> LoopbackTCPServer {
      try LoopbackTCPServer { _ in }
    }

    func start() throws -> UInt16 {
      let ready = DispatchSemaphore(value: 0)
      listener.stateUpdateHandler = { state in
        if case .ready = state { ready.signal() }
      }
      listener.newConnectionHandler = { [weak self] connection in
        guard let self else { return }
        self.connections.append(connection)
        connection.start(queue: self.queue)
        self.handle(connection)
      }
      listener.start(queue: queue)
      guard ready.wait(timeout: .now() + 5) == .success, let port = listener.port else {
        throw LoopbackError(message: "loopback TCP server failed to start")
      }
      return port.rawValue
    }

    func stop() {
      queue.sync {
        listener.cancel()
        for connection in connections { connection.cancel() }
        connections.removeAll()
      }
    }
  }
#endif
