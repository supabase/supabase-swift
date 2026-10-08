//
//  URLSessionWebSocketTransportTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 06/10/26.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
import TestHelpers
import Testing

@testable import Realtime

#if canImport(Network)
  import Network
#endif

@Suite(.serialized)
struct URLSessionWebSocketTransportTests {
  let transport = URLSessionWebSocketTransport()

  @Test
  func rejectsANonWebSocketSchemeWithANonRetryableTransportError() async {
    let error = await #expect(throws: RealtimeError.self) {
      _ = try await transport.connect(to: URL(string: "https://example.com")!, headerFields: [:])
    }
    #expect(error?.kind == .transport)
    #expect(error?.isRetryable == false)
  }

  #if canImport(Network)
    private func connect(port: UInt16) async throws -> any WebSocketConnection {
      try await transport.connect(to: URL(string: "ws://127.0.0.1:\(port)")!, headerFields: [:])
    }

    private func record(_ connection: any WebSocketConnection) -> (
      events: LockIsolated<[WebSocketEvent]>, finished: LockIsolated<Bool>
    ) {
      let events = LockIsolated([WebSocketEvent]())
      let finished = LockIsolated(false)
      Task {
        for await event in connection.events {
          events.withValue { $0.append(event) }
        }
        finished.setValue(true)
      }
      return (events, finished)
    }

    @Test
    func sendsFramesInCallOrder() async throws {
      let server = try LoopbackWebSocketServer()
      let port = try server.start()
      defer { server.stop() }

      let connection = try await connect(port: port)
      for index in 0..<50 {
        try await connection.send(.text("\(index)"))
      }
      #expect(await waitUntil { server.receivedMessages.count == 50 })
      let texts = server.receivedMessages.map { String(decoding: $0, as: UTF8.self) }
      #expect(texts == (0..<50).map(String.init))

      await connection.close(code: .normalClosure, reason: nil)
    }

    @Test
    func deliversTextAndBinaryFramesFromThePeer() async throws {
      let server = try LoopbackWebSocketServer()
      let port = try server.start()
      defer { server.stop() }

      let connection = try await connect(port: port)
      let (events, _) = record(connection)

      server.send(text: "hello")
      server.send(binary: Data([1, 2, 3]))
      #expect(await waitUntil { events.value.count == 2 })
      #expect(events.value == [.frame(.text("hello")), .frame(.binary(Data([1, 2, 3])))])

      await connection.close(code: .normalClosure, reason: nil)
    }

    @Test
    func closeFromTheClientIsTheFinalEventAndFinishesTheStream() async throws {
      let server = try LoopbackWebSocketServer()
      let port = try server.start()
      defer { server.stop() }

      let connection = try await connect(port: port)
      let (events, finished) = record(connection)

      await connection.close(code: .normalClosure, reason: "done")
      #expect(await waitUntil { finished.value })
      #expect(events.value == [.closed(code: .normalClosure, reason: "done")])
    }

    @Test
    func closeFromThePeerCarriesItsCodeAndReason() async throws {
      let server = try LoopbackWebSocketServer()
      let port = try server.start()
      defer { server.stop() }

      let connection = try await connect(port: port)
      let (events, finished) = record(connection)

      server.close(code: .protocolCode(.goingAway), reason: "bye")
      #expect(await waitUntil { finished.value })
      #expect(events.value == [.closed(code: .goingAway, reason: "bye")])
    }

    @Test
    func sendAfterCloseThrowsNotConnected() async throws {
      let server = try LoopbackWebSocketServer()
      let port = try server.start()
      defer { server.stop() }

      let connection = try await connect(port: port)
      let (_, finished) = record(connection)
      await connection.close(code: .normalClosure, reason: nil)
      #expect(await waitUntil { finished.value })

      let error = await #expect(throws: RealtimeError.self) {
        try await connection.send(.text("late"))
      }
      #expect(error?.kind == .notConnected)
    }

    @Test
    func refusedUpgradeThrowsANonRetryableUnauthorizedErrorWithTheStatus() async throws {
      let (server, _) = try LoopbackTCPServer.refusing(status: 401, reason: "Unauthorized")
      let port = try server.start()
      defer { server.stop() }

      let error = await #expect(throws: RealtimeError.self) {
        _ = try await connect(port: port)
      }
      #expect(error?.kind == .unauthorized)
      #expect(error?.isRetryable == false)
      #expect(error?.message.contains("401") == true)
    }

    @Test
    func refusedUpgradeWithAServerErrorIsRetryable() async throws {
      let (server, _) = try LoopbackTCPServer.refusing(status: 503, reason: "Unavailable")
      let port = try server.start()
      defer { server.stop() }

      let error = await #expect(throws: RealtimeError.self) {
        _ = try await connect(port: port)
      }
      #expect(error?.isRetryable == true)
      #expect(error?.message.contains("503") == true)
    }

    @Test
    func sendsHeaderFieldsWithTheUpgradeRequest() async throws {
      let (server, request) = try LoopbackTCPServer.refusing(status: 401, reason: "Unauthorized")
      let port = try server.start()
      defer { server.stop() }

      _ = try? await transport.connect(
        to: URL(string: "ws://127.0.0.1:\(port)")!,
        headerFields: [HTTPField.Name("x-api-key")!: "secret"]
      )
      #expect(request.value.lowercased().contains("x-api-key: secret"))
    }

    @Test
    func cancellingConnectRethrowsCancellationError() async throws {
      let server = try LoopbackTCPServer.stalling()
      let port = try server.start()
      defer { server.stop() }

      let task = Task { try await connect(port: port) }
      try await Task.sleep(for: .milliseconds(100))
      task.cancel()

      await #expect(throws: CancellationError.self) {
        _ = try await task.value
      }
    }
  #endif
}
