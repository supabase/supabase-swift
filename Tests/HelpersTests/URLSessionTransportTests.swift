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
import TestHelpers
import Testing

@testable import Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

// URLSession converts a POST/PUT `httpBody` into an `httpBodyStream` before a `URLProtocol`
// observes the request, so the bytes are read back from the stream. The stream is read until the
// writer closes it, which for a streamed request body means until the transport has pumped every
// chunk through.
extension URLRequest {
  fileprivate func testBodyData() -> Data? {
    guard let stream = httpBodyStream else { return httpBody }
    return stream.readToEnd()
  }
}

extension InputStream {
  fileprivate func readToEnd() -> Data {
    open()
    defer { close() }
    var data = Data()
    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }
    while true {
      let read = self.read(buffer, maxLength: bufferSize)
      guard read > 0 else { break }
      data.append(buffer, count: read)
    }
    return data
  }

  /// `readToEnd()` on a global queue. A bound pair's blocking read spins the calling thread's
  /// run loop while it waits, so it must never run on the test's own thread: in a full parallel
  /// run Swift Testing can place the test on the main thread, and parking the main run loop
  /// there deadlocks everything else that needs it.
  fileprivate func readToEndOffThread() async -> Data {
    let stream = UncheckedSendable(self)
    return await withCheckedContinuation { continuation in
      DispatchQueue.global().async { continuation.resume(returning: stream.value.readToEnd()) }
    }
  }
}

/// Answers each request with the stub registered for its URL. Every test uses its own URL, so
/// tests run in parallel without seeing each other's stubs.
private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
  struct Stub: Sendable {
    var method: String
    var url: URL
    var status: Int
    var headers: [String: String]
    var data: Data
    var onRequest: @Sendable (URLRequest) throws -> Void
  }

  private static let stubs = LockIsolated<[URL: Stub]>([:])

  static func register(_ stub: Stub) {
    stubs.withValue { $0[stub.url] = stub }
  }

  static func remove(_ url: URL) {
    stubs.withValue { $0[url] = nil }
  }

  override static func canInit(with request: URLRequest) -> Bool { true }

  override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard
      let url = request.url, let stub = Self.stubs.value[url], request.httpMethod == stub.method,
      let response = HTTPURLResponse(
        url: stub.url, statusCode: stub.status, httpVersion: "HTTP/1.1",
        headerFields: stub.headers)
    else {
      client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
      return
    }
    do {
      try stub.onRequest(request)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
      return
    }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: stub.data)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

@Suite
final class URLSessionTransportTests: Sendable {
  let url = URL(string: "https://\(UUID().uuidString.lowercased()).test/path")!

  deinit {
    StubURLProtocol.remove(url)
  }

  private func makeTransport(
    _ method: HTTPRequest.Method,
    status: Int = 200,
    headers: [String: String] = [:],
    data: Data = Data(),
    onRequest: @escaping @Sendable (URLRequest) throws -> Void = { _ in }
  ) -> URLSessionTransport {
    StubURLProtocol.register(
      .init(
        method: method.rawValue, url: url, status: status, headers: headers, data: data,
        onRequest: onRequest))
    return makeTransport()
  }

  private func makeTransport() -> URLSessionTransport {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return URLSessionTransport(session: URLSession(configuration: configuration))
  }

  @Test
  func getReturnsHeadAndStreamedBody() async throws {
    // The stub does not compute Content-Length from its data, so the header is supplied
    // explicitly here to give `URLResponse.expectedContentLength` a known value.
    let transport = makeTransport(
      .get, status: 201, headers: ["X-Test": "1", "Content-Length": "2"], data: Data("ok".utf8))

    let (head, maybeBody) = try await transport.send(
      HTTPRequest(method: .get, url: url), body: nil)

    #expect(head.status == 201)
    #expect(head.headerFields[HTTPField.Name("X-Test")!] == "1")
    let body = try #require(maybeBody)
    #if !canImport(FoundationNetworking)
      #expect(body.iterationBehavior == .single)
    #endif
    #expect(body.length == .known(2))
    let data = try await Data(collecting: body, upTo: 100)
    #expect(data == Data("ok".utf8))
  }

  @Test
  func dataBodyIsUploadedWithContentLength() async throws {
    let seen = LockIsolated<URLRequest?>(nil)
    let transport = makeTransport(.post) { request in seen.setValue(request) }

    _ = try await transport.send(
      HTTPRequest(method: .post, url: url), body: HTTPBody(Data("abc".utf8)))

    let request = try #require(seen.value)
    #expect(request.value(forHTTPHeaderField: "Content-Length") == "3")
    #expect(request.testBodyData() == Data("abc".utf8))
  }

  @Test
  func fileBodyIsUploadedFromDisk() async throws {
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data("file".utf8).write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let seen = LockIsolated<Data?>(nil)
    let transport = makeTransport(.put, data: Data("done".utf8)) { request in
      seen.setValue(request.testBodyData())
    }

    let (head, body) = try await transport.send(
      HTTPRequest(method: .put, url: url), body: try HTTPBody(fileURL: fileURL))

    #expect(head.status == 200)
    // swift-corelibs-foundation keeps a file upload on the task, not on the `URLRequest` that
    // the stub protocol observes, so the stub cannot see the body on Linux.
    #if !canImport(FoundationNetworking)
      #expect(seen.value == Data("file".utf8))
    #endif
    #expect(try await Data(collecting: try #require(body), upTo: 100) == Data("done".utf8))
  }

  @Test
  func streamedBodyIsPulledWhileTheRequestIsInFlight() async throws {
    let secondChunkReleased = LockIsolated(false)
    let releasedBeforeRequestStarted = LockIsolated<Bool?>(nil)
    let seenContentLength = LockIsolated<String?>(nil)
    let seenBody = LockIsolated<Data?>(nil)
    let (requestStarted, started) = AsyncStream<Void>.makeStream()
    let transport = makeTransport(.post) { request in
      releasedBeforeRequestStarted.setValue(secondChunkReleased.value)
      started.finish()
      seenContentLength.setValue(request.value(forHTTPHeaderField: "Content-Length"))
      seenBody.setValue(request.testBodyData())
    }

    let chunks = AsyncThrowingStream<ArraySlice<UInt8>, any Error> { continuation in
      continuation.yield(ArraySlice("abc".utf8))
      Task {
        #if !canImport(FoundationNetworking)
          for await _ in requestStarted {}
        #endif
        secondChunkReleased.setValue(true)
        continuation.yield(ArraySlice("def".utf8))
        continuation.finish()
      }
    }
    let body = HTTPBody(chunks, length: .known(6), iterationBehavior: .single)

    let (head, _) = try await transport.send(HTTPRequest(method: .post, url: url), body: body)

    #expect(head.status == 200)
    #if canImport(FoundationNetworking)
      #expect(releasedBeforeRequestStarted.value == true)
    #else
      #expect(releasedBeforeRequestStarted.value == false)
    #endif
    #expect(seenContentLength.value == "6")
    // Linux uploads the spooled file from the task, which the stub protocol cannot see.
    #if !canImport(FoundationNetworking)
      #expect(seenBody.value == Data("abcdef".utf8))
    #endif
  }

  #if canImport(FoundationNetworking)
    @Test
    func spooledBodyShorterThanDeclaredLengthFailsBeforeUploadOnLinux() async throws {
      let started = LockIsolated(false)
      let transport = makeTransport(.post) { _ in started.setValue(true) }
      let chunks = AsyncStream<ArraySlice<UInt8>> {
        $0.yield(ArraySlice("abc".utf8))
        $0.finish()
      }
      let body = HTTPBody(chunks, length: .known(6), iterationBehavior: .single)

      await #expect(throws: HTTPBodyLengthMismatchError.self) {
        _ = try await transport.send(HTTPRequest(method: .post, url: url), body: body)
      }
      #expect(started.value == false)
    }

    @Test
    func uploadProgressComesFromDidSendBodyDataOnLinux() {
      let seen = LockIsolated<[Int64]>([])
      let delegate = UploadProgressDelegate { bytes in seen.withValue { $0.append(bytes) } }
      let session = URLSession.shared
      let task = session.dataTask(with: url)

      delegate.urlSession(
        session, task: task, didSendBodyData: 2, totalBytesSent: 2, totalBytesExpectedToSend: 4)
      delegate.urlSession(
        session, task: task, didSendBodyData: 2, totalBytesSent: 4, totalBytesExpectedToSend: 4)

      #expect(seen.value == [2, 4])
    }
  #endif

  #if !canImport(FoundationNetworking)
    private func makeDelegate(requestBody: HTTPBody) -> (
      StreamingTaskDelegate, AsyncThrowingStream<ArraySlice<UInt8>, any Error>
    ) {
      let (chunks, continuation) = AsyncThrowingStream<ArraySlice<UInt8>, any Error>.makeStream()
      return (StreamingTaskDelegate(body: continuation, requestBody: requestBody), chunks)
    }

    @Test
    func fileBodyProgressComesFromDidSendBodyData() async throws {
      let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString)
      try Data("file".utf8).write(to: fileURL)
      defer { try? FileManager.default.removeItem(at: fileURL) }
      let seen = LockIsolated<[Int64]>([])
      let body = try HTTPBody(fileURL: fileURL)
        .reportingProgress { bytes in seen.withValue { $0.append(bytes) } }
      let (delegate, _) = makeDelegate(requestBody: body)
      let session = URLSession.shared
      let task = session.dataTask(with: url)

      delegate.urlSession(
        session, task: task, didSendBodyData: 2, totalBytesSent: 2, totalBytesExpectedToSend: 4)
      delegate.urlSession(
        session, task: task, didSendBodyData: 2, totalBytesSent: 4, totalBytesExpectedToSend: 4)

      #expect(seen.value == [2, 4])
    }

    @Test
    func streamedBodyProgressIsNotReportedTwice() async throws {
      let seen = LockIsolated<[Int64]>([])
      let chunks = AsyncStream<ArraySlice<UInt8>> { $0.finish() }
      let body = HTTPBody(chunks, length: .unknown, iterationBehavior: .single)
        .reportingProgress { bytes in seen.withValue { $0.append(bytes) } }
      let (delegate, _) = makeDelegate(requestBody: body)
      let session = URLSession.shared
      let task = session.dataTask(with: url)

      delegate.urlSession(
        session, task: task, didSendBodyData: 2, totalBytesSent: 2, totalBytesExpectedToSend: 4)

      #expect(seen.value.isEmpty)
    }

    @Test
    func singleBodyDoesNotFollowARedirectThatResendsIt() async throws {
      let redirected = LockIsolated<[URLRequest?]>([])
      let follow: @Sendable (URLRequest?) -> Void = { next in
        redirected.withValue { $0.append(next) }
      }
      let session = URLSession.shared
      let task = session.uploadTask(withStreamedRequest: URLRequest(url: url))
      let target = URLRequest(url: URL(string: "https://example.com/moved")!)
      func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
      }
      func body(_ behavior: HTTPBody.IterationBehavior) -> HTTPBody {
        HTTPBody(
          AsyncStream<ArraySlice<UInt8>> { $0.finish() }, length: .known(0),
          iterationBehavior: behavior)
      }

      let (single, _) = makeDelegate(requestBody: body(.single))
      single.urlSession(
        session, task: task, willPerformHTTPRedirection: response(307), newRequest: target,
        completionHandler: follow)
      single.urlSession(
        session, task: task, willPerformHTTPRedirection: response(308), newRequest: target,
        completionHandler: follow)
      single.urlSession(
        session, task: task, willPerformHTTPRedirection: response(303), newRequest: target,
        completionHandler: follow)
      let (multiple, _) = makeDelegate(requestBody: body(.multiple))
      multiple.urlSession(
        session, task: task, willPerformHTTPRedirection: response(307), newRequest: target,
        completionHandler: follow)

      #expect(redirected.value.map { $0?.url } == [nil, nil, target.url, target.url])
    }

    @Test
    func singleBodyFailsTheRequestOnASecondBodyStream() async throws {
      let chunks = AsyncStream<ArraySlice<UInt8>> { continuation in
        continuation.yield(ArraySlice("abcd".utf8))
        continuation.finish()
      }
      let body = HTTPBody(chunks, length: .known(4), iterationBehavior: .single)
      let (delegate, responseChunks) = makeDelegate(requestBody: body)
      let session = URLSession.shared
      let task = session.uploadTask(withStreamedRequest: URLRequest(url: url))

      let first = LockIsolated<UncheckedSendable<InputStream>?>(nil)
      delegate.urlSession(
        session, task: task,
        needNewBodyStream: { stream in
          let boxed = stream.map { UncheckedSendable($0) }
          first.setValue(boxed)
        })
      let firstStream = try #require(first.value?.value)
      #expect(await firstStream.readToEndOffThread() == Data("abcd".utf8))

      delegate.urlSession(session, task: task, needNewBodyStream: { _ in })
      let deadline = ContinuousClock.now + .seconds(2)
      while task.state == .suspended && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(5))
      }
      #expect(task.state != .suspended)

      delegate.urlSession(session, task: task, didCompleteWithError: URLError(.cancelled))
      await #expect(throws: HTTPBodyAlreadyConsumedError.self) {
        for try await _ in responseChunks {}
      }
    }
  #endif

  @Test
  func requestTimeoutTaskLocalIsAppliedToTheURLRequest() async throws {
    let seen = LockIsolated<TimeInterval?>(nil)
    let transport = makeTransport(.get) { request in seen.setValue(request.timeoutInterval) }

    try await RequestTimeout.$current.withValue(.seconds(150)) {
      _ = try await transport.send(HTTPRequest(method: .get, url: url), body: nil)
    }

    #expect(seen.value == 150)
  }

  @Test
  func streamedResponseDeliversChunksAsReceived() async throws {
    let payload = "data: 1\ndata: 2\ndata: 3\n"
    let transport = makeTransport(.get, data: Data(payload.utf8))

    var chunks: [String] = []
    let (_, maybeBody) = try await transport.send(
      HTTPRequest(method: .get, url: url), body: nil)
    for try await chunk in try #require(maybeBody) {
      chunks.append(String(decoding: chunk, as: UTF8.self))
    }

    // Chunk boundaries follow URLSession's deliveries, never the payload. The stub hands the
    // whole body over in one `didLoad`, so exactly one chunk arrives and nothing is re-split.
    #expect(chunks == [payload])
  }

  @Test
  func streamedResponseFailureSurfacesAsThrownError() async throws {
    let transport = makeTransport(.get) { _ in throw URLError(.notConnectedToInternet) }

    await #expect(throws: URLError.self) {
      _ = try await transport.send(HTTPRequest(method: .get, url: url), body: nil)
    }
  }

  #if !canImport(FoundationNetworking)
    @Test
    func uploadTaskExpectsTheBodyLength() throws {
      let transport = makeTransport()
      let request = URLRequest(url: url)
      let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString)
      try Data("file".utf8).write(to: fileURL)
      defer { try? FileManager.default.removeItem(at: fileURL) }
      let chunks = AsyncStream<ArraySlice<UInt8>> { $0.finish() }

      let file = transport.makeTask(for: request, body: try HTTPBody(fileURL: fileURL))
      let data = transport.makeTask(for: request, body: HTTPBody(Data("abc".utf8)))
      let stream = transport.makeTask(
        for: request, body: HTTPBody(chunks, length: .known(7), iterationBehavior: .single))
      let unknown = transport.makeTask(
        for: request, body: HTTPBody(chunks, length: .unknown, iterationBehavior: .single))
      let none = transport.makeTask(for: request, body: nil)

      #expect(file.countOfBytesClientExpectsToSend == 4)
      #expect(data.countOfBytesClientExpectsToSend == 3)
      #expect(stream.countOfBytesClientExpectsToSend == 7)
      #expect(unknown.countOfBytesClientExpectsToSend == NSURLSessionTransferSizeUnknown)
      #expect(none.countOfBytesClientExpectsToSend == NSURLSessionTransferSizeUnknown)
    }
  #endif
}
