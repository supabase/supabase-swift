//
//  RealtimeConnectTests.swift
//  RealtimeV3Tests
//
//  Created by Guilherme Souza on 29/06/26.
//

import Foundation
import Testing

@testable import RealtimeV3

@Suite struct RealtimeConnectTests {
  @Test func connectOpensTransportWithApiKey() async throws {
    let (transport, _) = InMemoryTransport.pair()
    let rt = Realtime(
      url: URL(string: "wss://proj.supabase.co/realtime/v1")!,
      apiKey: "anon",
      transport: transport
    )
    try await rt.connect()
    let url = await transport.lastConnectURL
    #expect(url?.query?.contains("apikey=anon") == true)
  }

  @Test func connectIsIdempotent() async throws {
    let (transport, _) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    try await rt.connect()
    try await rt.connect()
    #expect(await transport.connectCallCount == 1)
  }

  @Test func connectDrivesStatusToConnectingThenConnected() async throws {
    let (transport, _) = InMemoryTransport.pair()
    let rt = Realtime(
      url: URL(string: "wss://proj.supabase.co/realtime/v1")!,
      apiKey: "anon",
      transport: transport
    )

    // Subscribe to status before connecting so we catch all transitions.
    let stream = await rt.status

    // Connect in the background so we can read from the stream concurrently.
    async let connectResult: Void = rt.connect()

    var sawConnecting = false
    var sawConnected = false
    for await s in stream {
      switch s.state {
      case .connecting: sawConnecting = true
      case .connected:
        sawConnected = true
        break
      default: break
      }
      if sawConnected { break }
    }

    try await connectResult

    #expect(sawConnecting)
    #expect(sawConnected)
  }
}
