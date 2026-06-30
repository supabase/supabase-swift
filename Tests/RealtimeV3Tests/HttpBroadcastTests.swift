//
//  HttpBroadcastTests.swift
//  RealtimeV3Tests
//
//  Created by Guilherme Souza on 29/06/26.
//

import ConcurrencyExtras
import Foundation
import Mocker
import Testing

@testable import RealtimeV3

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite(.serialized) struct HttpBroadcastTests {

  func mockedSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockingURLProtocol.self]
    return URLSession(configuration: configuration)
  }

  @Test func single202Succeeds() async throws {
    // Mocker intercepts wss:// → converted to https:// inside Realtime
    let broadcastURL = URL(string: "https://proj.supabase.co/realtime/v1/api/broadcast")!

    let capturedRequest = LockIsolated<URLRequest?>(nil)
    var mock = Mock(
      url: broadcastURL,
      contentType: .json,
      statusCode: 202,
      data: [.post: Data()]
    )
    mock.onRequestHandler = OnRequestHandler(requestCallback: { capturedRequest.setValue($0) })
    mock.register()

    let rt = Realtime(
      url: URL(string: "wss://proj.supabase.co/realtime/v1")!,
      apiKey: "anon",
      urlSession: mockedSession()
    )
    let channel = await rt.channel("room:1")
    try await channel.httpBroadcast(event: "chat", payload: ["text": "hi"])

    let req = try #require(capturedRequest.value)
    // Body should be non-nil and contain "messages"
    let body = req.httpBodyStreamData() ?? req.httpBody
    let bodyString = body.map { String(decoding: $0, as: UTF8.self) } ?? ""
    #expect(body != nil)
    #expect(bodyString.contains("messages"))

    // No token configured → apikey header must be present
    #expect(req.value(forHTTPHeaderField: "apikey") == "anon")
  }

  @Test func rateLimitedThrows() async throws {
    let broadcastURL = URL(string: "https://proj.supabase.co/realtime/v1/api/broadcast")!
    Mock(
      url: broadcastURL,
      contentType: .json,
      statusCode: 429,
      data: [.post: Data(#"{"message":"Too many requests"}"#.utf8)]
    ).register()

    let rt = Realtime(
      url: URL(string: "wss://proj.supabase.co/realtime/v1")!,
      apiKey: "anon",
      urlSession: mockedSession()
    )
    let channel = await rt.channel("room:1")

    do {
      try await channel.httpBroadcast(event: "chat", payload: ["text": "hi"])
      Issue.record("Expected rateLimited error but call succeeded")
    } catch {
      if case .rateLimited = error {
        // expected
      } else {
        Issue.record("Expected .rateLimited, got: \(error)")
      }
    }
  }

  @Test func batchSendsMultipleMessages() async throws {
    let broadcastURL = URL(string: "https://proj.supabase.co/realtime/v1/api/broadcast")!

    let capturedRequest = LockIsolated<URLRequest?>(nil)
    var mock = Mock(
      url: broadcastURL,
      contentType: .json,
      statusCode: 202,
      data: [.post: Data()]
    )
    mock.onRequestHandler = OnRequestHandler(requestCallback: { capturedRequest.setValue($0) })
    mock.register()

    let rt = Realtime(
      url: URL(string: "wss://proj.supabase.co/realtime/v1")!,
      apiKey: "anon",
      urlSession: mockedSession()
    )

    let messages: [HttpBroadcastMessage] = [
      HttpBroadcastMessage(topic: "room:1", event: "chat", payload: ["text": "hello"]),
      HttpBroadcastMessage(topic: "room:2", event: "status", payload: ["online": true]),
    ]
    try await rt.httpBroadcastBatch(messages)

    let req = try #require(capturedRequest.value)
    let body = req.httpBodyStreamData() ?? req.httpBody
    let bodyString = body.map { String(decoding: $0, as: UTF8.self) } ?? ""
    #expect(body != nil)
    // Body should contain both topics
    #expect(bodyString.contains("room:1"))
    #expect(bodyString.contains("room:2"))
  }
}

// MARK: - URLRequest extension for body capture in tests

extension URLRequest {
  fileprivate func httpBodyStreamData() -> Data? {
    guard let bodyStream = httpBodyStream else { return nil }
    bodyStream.open()
    let bufferSize = 16
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    var data = Data()
    while bodyStream.hasBytesAvailable {
      let readData = bodyStream.read(buffer, maxLength: bufferSize)
      data.append(buffer, count: readData)
    }
    buffer.deallocate()
    bodyStream.close()
    return data
  }
}
