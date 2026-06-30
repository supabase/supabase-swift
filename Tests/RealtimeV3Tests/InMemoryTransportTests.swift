import Foundation
import Testing

@testable import RealtimeV3

@Suite struct InMemoryTransportTests {
  @Test func clientSendReachesServer() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let conn = try await transport.connect(to: URL(string: "wss://x")!, headers: [:])
    try await conn.send(.text("hello"))
    var it = server.clientSentFrames.makeAsyncIterator()
    let frame = await it.next()
    #expect(frame == .text("hello"))
  }

  @Test func serverSendReachesClient() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let conn = try await transport.connect(to: URL(string: "wss://x")!, headers: [:])
    server.send(.text("world"))
    var it = conn.frames.makeAsyncIterator()
    let frame = try await it.next()
    #expect(frame == .text("world"))
  }
}
