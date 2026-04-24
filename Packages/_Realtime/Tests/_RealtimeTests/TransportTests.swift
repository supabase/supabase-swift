import Testing
import Foundation
import ConcurrencyExtras
@testable import _Realtime

@Suite struct TransportTests {
  @Test func framesFlowClientToServer() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let connection = try await transport.connect(to: URL(string: "ws://test")!, headers: [:])

    try await connection.send(.text("hello"))
    let received = await server.receive()
    #expect(received == .text("hello"))
  }

  @Test func framesFlowServerToClient() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let connection = try await transport.connect(to: URL(string: "ws://test")!, headers: [:])

    Task { await server.send(.text("from server")) }

    var iter = connection.frames.makeAsyncIterator()
    let frame = try await iter.next()
    #expect(frame == .text("from server"))
  }

  @Test func serverCloseFinishesClientFrames() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let connection = try await transport.connect(to: URL(string: "ws://test")!, headers: [:])

    Task { server.close() }

    var receivedFrames: [TransportFrame] = []
    do {
      for try await frame in connection.frames {
        receivedFrames.append(frame)
      }
    } catch {
      // close with error is fine
    }
    #expect(receivedFrames.isEmpty)
  }
}
