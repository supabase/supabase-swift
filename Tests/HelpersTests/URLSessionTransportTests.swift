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
import TestHelpers
import Testing

@testable import Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

// Mocker 3.0.2's `URLRequest.httpBodyStreamData()` is a `private extension`, not `public` as
// documented, so it isn't visible here. URLSession converts a POST/PUT `httpBody` into an
// `httpBodyStream` before `MockingURLProtocol` observes the request, so tests need their own
// reader to recover the bytes. The stream is read until the writer closes it, which for a
// streamed request body means until the transport has pumped every chunk through.
extension URLRequest {
  fileprivate func testBodyData() -> Data? {
    guard let stream = httpBodyStream else { return httpBody }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }
    while true {
      let read = stream.read(buffer, maxLength: bufferSize)
      guard read > 0 else { break }
      data.append(buffer, count: read)
    }
    return data
  }
}

// Mocker's registry (`Mock.register()`, `Mocker.removeAll()`) is process-global, and each test
// calls `removeAll()` in `makeTransport()`, so two tests running concurrently can wipe out one
// another's registered mock. `.serialized` keeps this suite's own tests from racing, and
// `.mockerSerialized` extends that to Mocker-backed suites in every other test target.
@Suite(.serialized, .mockerSerialized)
struct URLSessionTransportTests {
  let url = URL(string: "https://example.com/path")!

  private func makeTransport() -> URLSessionTransport {
    Mocker.removeAll()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockingURLProtocol.self]
    return URLSessionTransport(session: URLSession(configuration: configuration))
  }

  @Test
  func getReturnsHeadAndStreamedBody() async throws {
    let transport = makeTransport()
    // Mocker doesn't compute Content-Length from the mocked data itself, so the header is
    // supplied explicitly here to give `URLResponse.expectedContentLength` a known value.
    Mock(
      url: url, statusCode: 201,
      data: [.get: Data("ok".utf8)],
      additionalHeaders: ["X-Test": "1", "Content-Length": "2"]
    ).register()

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
    // swift-corelibs-foundation keeps a file upload on the task, not on the `URLRequest` that
    // `MockingURLProtocol` observes, so the mock cannot see the body on Linux.
    #if !canImport(FoundationNetworking)
      #expect(seen.value == Data("file".utf8))
    #endif
    #expect(try await Data(collecting: try #require(body), upTo: 100) == Data("done".utf8))
  }

  @Test
  func streamedBodyIsPulledWhileTheRequestIsInFlight() async throws {
    let transport = makeTransport()
    var mock = Mock(url: url, statusCode: 200, data: [.post: Data()])
    let secondChunkReleased = LockIsolated(false)
    let releasedBeforeRequestStarted = LockIsolated<Bool?>(nil)
    let seenContentLength = LockIsolated<String?>(nil)
    let seenBody = LockIsolated<Data?>(nil)
    let (requestStarted, started) = AsyncStream<Void>.makeStream()
    mock.onRequestHandler = OnRequestHandler(requestCallback: { request in
      releasedBeforeRequestStarted.setValue(secondChunkReleased.value)
      started.finish()
      seenContentLength.setValue(request.value(forHTTPHeaderField: "Content-Length"))
      seenBody.setValue(request.testBodyData())
    })
    mock.register()

    // The second chunk is held back until the request has started. A streaming transport starts
    // with the first chunk and then drains the second; a transport that collects the body first
    // would never start (Linux does collect first, so there the gate is skipped and the flag is
    // set before the request can begin).
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
      // Linux spools the body before the request starts (documented on the transport).
      #expect(releasedBeforeRequestStarted.value == true)
    #else
      #expect(releasedBeforeRequestStarted.value == false)
    #endif
    #expect(seenContentLength.value == "6")
    // Linux uploads the spooled file from the task, which `MockingURLProtocol` cannot see.
    #if !canImport(FoundationNetworking)
      #expect(seenBody.value == Data("abcdef".utf8))
    #endif
  }

  #if canImport(FoundationNetworking)
    @Test
    func spooledBodyShorterThanDeclaredLengthFailsBeforeUploadOnLinux() async throws {
      let transport = makeTransport()
      let started = LockIsolated(false)
      var mock = Mock(url: url, statusCode: 200, data: [.post: Data()])
      mock.onRequestHandler = OnRequestHandler(requestCallback: { _ in started.setValue(true) })
      mock.register()
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
    func fileBodyProgressReportsOnceOnCompletionOnLinux() async throws {
      let transport = makeTransport()
      let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString)
      try Data("file".utf8).write(to: fileURL)
      defer { try? FileManager.default.removeItem(at: fileURL) }
      Mock(url: url, statusCode: 200, data: [.put: Data()]).register()
      let seen = LockIsolated<[Int64]>([])

      _ = try await transport.send(
        HTTPRequest(method: .put, url: url),
        body: try HTTPBody(fileURL: fileURL).reportingProgress { bytes in
          seen.withValue { $0.append(bytes) }
        })

      // No per-task delegate here, so the only honest report is the total, after the fact.
      #expect(seen.value == [4])
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

      // A streamed body reports as its chunks are pulled, so the task-level callback stays quiet.
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

      // 307/308 resend the body, which a one-shot body cannot do, so the 3xx is handed back.
      let (single, _) = makeDelegate(requestBody: body(.single))
      single.urlSession(
        session, task: task, willPerformHTTPRedirection: response(307), newRequest: target,
        completionHandler: follow)
      single.urlSession(
        session, task: task, willPerformHTTPRedirection: response(308), newRequest: target,
        completionHandler: follow)
      // 303 turns the request into a bodiless GET, so nothing needs replaying.
      single.urlSession(
        session, task: task, willPerformHTTPRedirection: response(303), newRequest: target,
        completionHandler: follow)
      // A body that can replay follows every redirect.
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
      var request = URLRequest(url: url)
      request.httpBodyStream = try #require(first.value?.value)
      #expect(request.testBodyData() == Data("abcd".utf8))

      // A redirect or auth retry asks for the body again. The one-shot body cannot replay, so
      // the delegate cancels the task and reports why instead of a bare `URLError.cancelled`.
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
    let transport = makeTransport()
    var mock = Mock(url: url, statusCode: 200, data: [.get: Data()])
    let seen = LockIsolated<TimeInterval?>(nil)
    mock.onRequestHandler = OnRequestHandler(requestCallback: { request in
      seen.setValue(request.timeoutInterval)
    })
    mock.register()

    try await RequestTimeout.$current.withValue(.seconds(150)) {
      _ = try await transport.send(HTTPRequest(method: .get, url: url), body: nil)
    }

    #expect(seen.value == 150)
  }

  @Test
  func streamedResponseDeliversChunksAsReceived() async throws {
    let transport = makeTransport()
    let payload = "data: 1\ndata: 2\ndata: 3\n"
    Mock(url: url, statusCode: 200, data: [.get: Data(payload.utf8)]).register()

    var chunks: [String] = []
    let (_, maybeBody) = try await transport.send(
      HTTPRequest(method: .get, url: url), body: nil)
    for try await chunk in try #require(maybeBody) {
      chunks.append(String(decoding: chunk, as: UTF8.self))
    }

    // Chunk boundaries follow URLSession's deliveries, never the payload. Mocker hands the
    // whole body over in one `didLoad`, so exactly one chunk arrives and nothing is re-split.
    #expect(chunks == [payload])
  }

  @Test
  func streamedResponseFailureSurfacesAsThrownError() async throws {
    let transport = makeTransport()
    Mock(
      url: url, statusCode: 200, data: [.get: Data()],
      requestError: URLError(.notConnectedToInternet)
    ).register()

    await #expect(throws: URLError.self) {
      _ = try await transport.send(HTTPRequest(method: .get, url: url), body: nil)
    }
  }
}
