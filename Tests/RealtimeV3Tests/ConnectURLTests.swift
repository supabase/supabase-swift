//
//  ConnectURLTests.swift
//  RealtimeV3Tests
//
//  Created by Guilherme Souza on 30/06/26.
//

import Foundation
import Testing

@testable import RealtimeV3

@Suite struct ConnectURLTests {
  private func query(_ url: URL) -> [String: String] {
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    return Dictionary(
      items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
  }

  @Test func appendsWebsocketAndQueryItems() throws {
    let url = try Realtime._connectURL(
      base: URL(string: "wss://x.supabase.co/realtime/v1")!, apiKey: "anon", vsn: "2.0.0")
    #expect(url.path == "/realtime/v1/websocket")
    let q = query(url)
    #expect(q["apikey"] == "anon")
    #expect(q["vsn"] == "2.0.0")
  }

  @Test func handlesTrailingSlashWithoutDoublingIt() throws {
    let url = try Realtime._connectURL(
      base: URL(string: "wss://x.supabase.co/realtime/v1/")!, apiKey: "anon", vsn: "2.0.0")
    #expect(url.path == "/realtime/v1/websocket")
  }

  @Test func doesNotDoubleAppendWebsocket() throws {
    let url = try Realtime._connectURL(
      base: URL(string: "wss://x.supabase.co/realtime/v1/websocket")!, apiKey: "anon", vsn: "2.0.0")
    #expect(url.path == "/realtime/v1/websocket")
  }

  @Test func replacesPreexistingApikeyAndVsn() throws {
    let url = try Realtime._connectURL(
      base: URL(string: "wss://x.supabase.co/realtime/v1?apikey=stale&vsn=1.0.0&keep=1")!,
      apiKey: "fresh", vsn: "2.0.0")
    let q = query(url)
    #expect(q["apikey"] == "fresh")
    #expect(q["vsn"] == "2.0.0")
    // Unrelated query items are preserved.
    #expect(q["keep"] == "1")
    // No duplicate apikey/vsn entries survive.
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    #expect(items.filter { $0.name == "apikey" }.count == 1)
    #expect(items.filter { $0.name == "vsn" }.count == 1)
  }
}
