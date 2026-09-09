//
//  URLSessionTransportTests.swift
//  HelpersTests
//
//  Created by Guilherme Souza on 09/09/26.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
import HTTPTypesFoundation
import Mocker
import Testing

@testable import Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

// Mocker 3.0.2's `URLRequest.httpBodyStreamData()` is a `private extension`, not `public` as
// documented, so it isn't visible here. URLSession converts a POST/PUT `httpBody` into an
// `httpBodyStream` before `MockingURLProtocol` observes the request, so tests need their own
// reader to recover the bytes.
extension URLRequest {
  fileprivate func testBodyData() -> Data? {
    guard let stream = httpBodyStream else { return httpBody }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
      let read = stream.read(buffer, maxLength: bufferSize)
      guard read > 0 else { break }
      data.append(buffer, count: read)
    }
    return data
  }
}

// Mocker's registry (`Mock.register()`, `Mocker.removeAll()`) is process-global, and each test
// calls `removeAll()` in `makeTransport()`, so two tests running concurrently can wipe out one
// another's registered mock. `.serialized` keeps them from racing.
@Suite(.serialized)
struct URLSessionTransportTests {
  let url = URL(string: "https://example.com/path")!

  private func makeTransport() -> URLSessionTransport {
    Mocker.removeAll()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockingURLProtocol.self]
    return URLSessionTransport(session: URLSession(configuration: configuration))
  }

  @Test
  func bufferedGetReturnsHeadAndBody() async throws {
    let transport = makeTransport()
    Mock(
      url: url, statusCode: 201,
      data: [.get: Data("ok".utf8)],
      additionalHeaders: ["X-Test": "1"]
    ).register()

    let (head, body) = try await transport.send(
      HTTPRequest(method: .get, url: url), body: nil)

    #expect(head.status == 201)
    #expect(head.headerFields[HTTPField.Name("X-Test")!] == "1")
    let data = try await Data(collecting: try #require(body), upTo: 100)
    #expect(data == Data("ok".utf8))
  }

  @Test
  func dataBodyIsUploadedWithContentLength() async throws {
    let transport = makeTransport()
    var mock = Mock(url: url, statusCode: 200, data: [.post: Data()])
    let seen = LockIsolated<URLRequest?>(nil)
    mock.onRequestHandler = OnRequestHandler(requestCallback: { request in seen.setValue(request) })
    mock.register()

    _ = try await transport.send(
      HTTPRequest(method: .post, url: url), body: HTTPBody(Data("abc".utf8)))

    let request = try #require(seen.value)
    #expect(request.value(forHTTPHeaderField: "Content-Length") == "3")
    #expect(request.testBodyData() == Data("abc".utf8))
  }

  @Test
  func fileBodyIsUploadedFromDisk() async throws {
    let transport = makeTransport()
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data("file".utf8).write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    var mock = Mock(url: url, statusCode: 200, data: [.put: Data("done".utf8)])
    let seen = LockIsolated<Data?>(nil)
    mock.onRequestHandler = OnRequestHandler(requestCallback: { request in
      seen.setValue(request.testBodyData())
    })
    mock.register()

    let (head, body) = try await transport.send(
      HTTPRequest(method: .put, url: url), body: try HTTPBody(fileURL: fileURL))

    #expect(head.status == 200)
    #expect(seen.value == Data("file".utf8))
    #expect(try await Data(collecting: try #require(body), upTo: 100) == Data("done".utf8))
  }

  @Test
  func requestTimeoutTaskLocalIsAppliedToTheURLRequest() async throws {
    let transport = makeTransport()
    var mock = Mock(url: url, statusCode: 200, data: [.get: Data()])
    let seen = LockIsolated<TimeInterval?>(nil)
    mock.onRequestHandler = OnRequestHandler(requestCallback: { request in
      seen.setValue(request.timeoutInterval)
    })
    mock.register()

    try await RequestTimeout.$current.withValue(150) {
      _ = try await transport.send(HTTPRequest(method: .get, url: url), body: nil)
    }

    #expect(seen.value == 150)
  }
}
