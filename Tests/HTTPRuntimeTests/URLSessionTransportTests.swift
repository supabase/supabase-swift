//
//  URLSessionTransportTests.swift
//  HTTPRuntime
//
//  Created by Guilherme Souza on 25/08/26.
//
import Foundation
import HTTPTypes
import Testing

@testable import HTTPRuntime

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Captures the outgoing `URLRequest` and replays a canned response, so the
/// transport can be exercised without a network.
private final class RecordingURLProtocol: URLProtocol {
  // These deliberately carry no lock, and must stay that way — a lock here
  // would fight the design rather than protect it. Two things make the
  // unchecked access safe. `@Suite(.serialized)` means only one test at a time
  // owns the class, so there are never two concurrent writers. And URLSession
  // finishes `startLoading` before it resumes the continuation the test is
  // awaiting, which orders the protocol's writes before the test's reads.
  nonisolated(unsafe) static var lastRequest: URLRequest?
  nonisolated(unsafe) static var responseStatus = 200
  nonisolated(unsafe) static var responseBody = Data()

  static func reset() {
    lastRequest = nil
    responseStatus = 200
    responseBody = Data()
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    // `httpBody` is nil for stream-backed uploads, so read the stream when
    // that is how URLSession handed the body over.
    var recorded = request
    if recorded.httpBody == nil, let stream = recorded.httpBodyStream {
      var collected = Data()
      stream.open()
      let size = 4096
      let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
      defer { buffer.deallocate() }
      while stream.hasBytesAvailable {
        let read = stream.read(buffer, maxLength: size)
        if read <= 0 { break }
        collected.append(buffer, count: read)
      }
      stream.close()
      recorded.httpBody = collected
    }
    Self.lastRequest = recorded

    let response = HTTPURLResponse(
      url: request.url!, statusCode: Self.responseStatus, httpVersion: "HTTP/1.1",
      headerFields: ["X-Stub": "yes"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Self.responseBody)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

private func makeTransport() -> URLSessionTransport {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [RecordingURLProtocol.self]
  return URLSessionTransport(configuration: configuration)
}

/// Asserts on an upload's body only where the test double can actually see it.
///
/// `URLSession.upload(for:from:)` and `upload(for:fromFile:)` do not hand the
/// request body to a custom `URLProtocol` on swift-corelibs-foundation: the
/// recorded request arrives with `httpBody` nil AND `httpBodyStream` nil, so
/// there is nothing to read. Verified against Swift 6.2.4 on Linux.
///
/// This is a limitation of the observation mechanism, not of
/// `URLSessionTransport` — the upload itself still runs on Linux, and the
/// surrounding assertions (method, URL, headers, response) hold on both
/// platforms. A request whose `httpBody` is set directly, as
/// `stream(_:body:)` does, propagates fine on corelibs, which is why
/// `streamTransmitsADataBody` asserts its payload unconditionally.
private func assertBodyIfObservable(
  _ request: URLRequest,
  equals payload: Data,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  #if canImport(FoundationNetworking)
    #expect(
      request.httpBody == nil,
      "corelibs is expected to drop an upload body; if this now arrives, drop the platform gate",
      sourceLocation: sourceLocation)
  #else
    #expect(request.httpBody == payload, sourceLocation: sourceLocation)
  #endif
}

@Suite(.serialized)
struct URLSessionTransportTests {
  @Test
  func sendCarriesMethodPathQueryAndHeaders() async throws {
    RecordingURLProtocol.reset()
    RecordingURLProtocol.responseStatus = 201
    RecordingURLProtocol.responseBody = Data(#"{"ok":true}"#.utf8)

    var builder = HTTPRequestBuilder(
      method: .post, baseURL: URL(string: "https://example.com")!, path: "/v1/things")
    builder.addQuery("select", "name")
    builder.setHeader(.contentType, "application/json")
    let request = try builder.build()

    let response = try await makeTransport().send(request, body: nil, uploadProgress: nil)

    let sent = try #require(RecordingURLProtocol.lastRequest)
    #expect(sent.httpMethod == "POST")
    #expect(sent.url?.absoluteString == "https://example.com/v1/things?select=name")
    #expect(sent.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(response.head.status == 201)
    #expect(response.head.headerFields[HTTPField.Name("X-Stub")!] == "yes")
    #expect(response.body == Data(#"{"ok":true}"#.utf8))
  }

  @Test
  func sendTransmitsADataBody() async throws {
    RecordingURLProtocol.reset()
    let payload = Data(#"{"name":"widget"}"#.utf8)

    var builder = HTTPRequestBuilder(
      method: .post, baseURL: URL(string: "https://example.com")!, path: "/v1/things")
    builder.setHeader(.contentType, "application/json")
    let request = try builder.build()

    _ = try await makeTransport().send(request, body: .data(payload), uploadProgress: nil)

    let sent = try #require(RecordingURLProtocol.lastRequest)
    #expect(sent.httpMethod == "POST")
    assertBodyIfObservable(sent, equals: payload)
  }

  @Test
  func sendTransmitsAFileBody() async throws {
    RecordingURLProtocol.reset()
    let payload = Data(#"{"name":"from-disk"}"#.utf8)
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("upload-\(UUID().uuidString).json")
    try payload.write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let builder = HTTPRequestBuilder(
      method: .put, baseURL: URL(string: "https://example.com")!, path: "/v1/things/1")
    let request = try builder.build()

    _ = try await makeTransport().send(request, body: .file(fileURL), uploadProgress: nil)

    let sent = try #require(RecordingURLProtocol.lastRequest)
    #expect(sent.httpMethod == "PUT")
    assertBodyIfObservable(sent, equals: payload)
  }

  @Test
  func streamRejectsAFileBody() async throws {
    RecordingURLProtocol.reset()
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("reject-\(UUID().uuidString).bin")
    try Data("x".utf8).write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let builder = HTTPRequestBuilder(
      method: .post, baseURL: URL(string: "https://example.com")!, path: "/v1/events")
    let request = try builder.build()

    do {
      _ = try await makeTransport().stream(request, body: .file(fileURL))
      Issue.record("expected stream to reject a file body")
    } catch {
      guard case .unsupportedRequestBody = error else {
        Issue.record("expected .unsupportedRequestBody, got \(error)")
        return
      }
    }
  }

  @Test
  func streamYieldsTheResponseBody() async throws {
    RecordingURLProtocol.reset()
    RecordingURLProtocol.responseBody = Data("line one\nline two\n".utf8)

    let builder = HTTPRequestBuilder(
      method: .get, baseURL: URL(string: "https://example.com")!, path: "/v1/events")
    let request = try builder.build()

    let response = try await makeTransport().stream(request, body: nil)
    var collected = Data()
    for try await chunk in response.body { collected.append(chunk) }

    #expect(response.head.status == 200)
    #expect(collected == Data("line one\nline two\n".utf8))
  }

  @Test
  func streamTransmitsADataBody() async throws {
    RecordingURLProtocol.reset()
    RecordingURLProtocol.responseBody = Data("event: ok\n".utf8)
    let payload = Data(#"{"topic":"events"}"#.utf8)

    var builder = HTTPRequestBuilder(
      method: .post, baseURL: URL(string: "https://example.com")!, path: "/v1/events")
    builder.setHeader(.contentType, "application/json")
    let request = try builder.build()

    let response = try await makeTransport().stream(request, body: .data(payload))
    var collected = Data()
    for try await chunk in response.body { collected.append(chunk) }

    let sent = try #require(RecordingURLProtocol.lastRequest)
    #expect(sent.httpMethod == "POST")
    #expect(sent.httpBody == payload)
    #expect(response.head.status == 200)
    #expect(collected == Data("event: ok\n".utf8))
  }
}
